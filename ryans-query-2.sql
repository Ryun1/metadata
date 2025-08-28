/* =======================================================================
   SPO voting (ledger-style) for NewCommittee actions (non-bootstrap)
   -----------------------------------------------------------------------
   What this query returns (one row per NewCommittee action):
     - Weighted SPO votes: pool_yes_votes / pool_no_votes / pool_abstain_votes
     - Total pool voting power at the proposal’s cutoff epoch
     - Voting power of SPOs that voted vs. did not vote
     - Diagnostics:
         * spo_auto_abstain_voting_power        : non-voting SPO power whose REWARD ADDRESS delegates to drep_always_abstain
         * spo_no_confidence_voting_power       : non-voting SPO power whose REWARD ADDRESS delegates to drep_always_no_confidence
     - Ledger-style effective folding (non-bootstrap, NewCommittee):
         * spo_yes_power_effective              : explicit Yes only (no auto -> Yes folding for NewCommittee)
         * spo_abstain_power_effective          : Abstain explicit + auto-abstain (reward addr special)
         * spo_denominator_effective            : total - effective_abstain
         * spo_yes_ratio_pct_effective          : yes / (total - abstain), percent

   Key modeling choices:
     • Only NewCommittee proposals (db-sync uses 'NewCommittee' not 'UpdateCommittee').
     • We are NOT in bootstrap phase (per your requirement).
     • For non-voters (ledger semantics for NewCommittee):
         - Default = No
         - If reward address delegates to AlwaysAbstain -> Abstain
         - If reward address delegates to AlwaysNoConfidence -> No  (not Yes; Yes special-case applies to NoConfidence actions only)
     • Exclude RETIRED pools at the cutoff (retiring_epoch <= cutoff).
     • Pool voting power snapshot: latest pool_stat <= cutoff (per action).
     • Deduplicate pool_stat deterministically with DISTINCT ON (pool_hash_id, epoch_no ORDER BY id DESC).

   Toggling epoch:
     - Set EpochSelector.selected_epoch to a fixed epoch (e.g., 579) OR to current MAX(no).
     - The per-action cutoff is: LEAST(relevant_epoch_of_action, selected_epoch).

   Performance notes:
     - Ensure indexes exist on:
         voting_procedure(gov_action_proposal_id, pool_voter, tx_id)
         pool_stat(pool_hash_id, epoch_no, id)
         pool_update(hash_id, active_epoch_no, registered_tx_id)
         pool_retire(hash_id, retiring_epoch)
         tx(id, block_id), block(id, epoch_no)
         delegation_vote(addr_id, tx_id), drep_hash(id, view)
         gov_action_proposal(id, type, ratified_epoch, expired_epoch, dropped_epoch, tx_id)
     - DISTINCT ON is PostgreSQL-specific and efficient when supported by an index ordering.
   ======================================================================= */

WITH
EpochSelector AS (
  SELECT 579::integer AS selected_epoch            -- <<<<< FIXED: use epoch 579
  -- SELECT (SELECT MAX(no) FROM epoch) AS selected_epoch  -- <<<<< CURRENT: use latest epoch
),

/* -----------------------------------------------------------------------
   TargetAction
   -----------------------------------------------------------------------
   Restrict to governance actions of type 'NewCommittee' (db-sync enum).
-------------------------------------------------------------------------*/
TargetAction AS (
  SELECT 
      gap.id,         -- proposal id
      gap.tx_id,      -- creating tx id
      gap.index,      -- index within that tx
      gap.type        -- enum govactiontype ('NewCommittee' here)
  FROM gov_action_proposal gap
  JOIN tx ON tx.id = gap.tx_id
  WHERE gap.type = 'NewCommittee'
),

/* -----------------------------------------------------------------------
   ActionEpoch
   -----------------------------------------------------------------------
   For each target action, compute its "relevant epoch", then clamp by the
   user-selected epoch. This is the snapshot cutoff we use for votes/power.
   relevant_epoch (status-based):
     - ratified_epoch (if present)
     - else expired_epoch
     - else dropped_epoch
     - else latest_epoch (MAX(no))
-------------------------------------------------------------------------*/
ActionEpoch AS (
  SELECT 
      ta.id,
      LEAST(
        CASE 
          WHEN gap.ratified_epoch IS NOT NULL THEN gap.ratified_epoch
          WHEN gap.expired_epoch  IS NOT NULL THEN gap.expired_epoch
          WHEN gap.dropped_epoch  IS NOT NULL THEN gap.dropped_epoch
          ELSE (SELECT MAX(no) FROM epoch)
        END,
        es.selected_epoch
      ) AS cutoff_epoch
  FROM TargetAction ta
  JOIN gov_action_proposal gap ON gap.id = ta.id
  CROSS JOIN EpochSelector es
),

/* -----------------------------------------------------------------------
   PoolStatDedup
   -----------------------------------------------------------------------
   Deduplicate pool_stat per (pool_hash_id, epoch_no). If multiple rows
   exist for the same (pool, epoch), we deterministically pick the one
   with the largest id (assumed “latest”).
   Using DISTINCT ON keeps exactly one row per (pool, epoch).
-------------------------------------------------------------------------*/
PoolStatDedup AS (
  SELECT DISTINCT ON (ps.pool_hash_id, ps.epoch_no)
    ps.pool_hash_id,
    ps.epoch_no,
    ps.voting_power
  FROM pool_stat ps
  ORDER BY ps.pool_hash_id, ps.epoch_no, ps.id DESC
),

/* -----------------------------------------------------------------------
   RankedPoolStats
   -----------------------------------------------------------------------
   For each action, take the latest pool_stat snapshot at or before the
   action cutoff. We do this per (pool, action) and rank by epoch_no DESC.
   rn = 1 -> the row we use as the pool's voting power at cutoff.
-------------------------------------------------------------------------*/
RankedPoolStats AS (
  SELECT 
      psd.pool_hash_id,
      psd.epoch_no,
      psd.voting_power,
      ae.cutoff_epoch,
      ae.id AS action_id,
      ROW_NUMBER() OVER (
        PARTITION BY psd.pool_hash_id, ae.id 
        ORDER BY psd.epoch_no DESC
      ) AS rn
  FROM PoolStatDedup psd
  JOIN ActionEpoch ae ON psd.epoch_no <= ae.cutoff_epoch
),

/* -----------------------------------------------------------------------
   RankedPoolUpdates
   -----------------------------------------------------------------------
   Latest pool_update at/before cutoff per (pool, action). We need this
   to:
     1) infer the REWARD ADDRESS at cutoff (reward_addr_id)
     2) derive pool activeness (combined with pool_retire, below)
   Rank by (active_epoch_no DESC, id DESC).
-------------------------------------------------------------------------*/
RankedPoolUpdates AS (
  SELECT
    pu.id,
    ph.id        AS pool_hash_id,
    pu.reward_addr_id,         -- stake_address.id used as rewards address
    ae.id        AS gov_action_id,
    ae.cutoff_epoch,
    ROW_NUMBER() OVER (
      PARTITION BY ph.id, ae.id
      ORDER BY pu.active_epoch_no DESC, pu.id DESC
    ) AS rn
  FROM pool_update pu
  JOIN pool_hash ph ON pu.hash_id = ph.id
  JOIN tx putx     ON putx.id = pu.registered_tx_id
  JOIN block pub   ON pub.id = putx.block_id
  JOIN ActionEpoch ae ON pub.epoch_no <= ae.cutoff_epoch
),

/* -----------------------------------------------------------------------
   ActivePoolsAtCutoff
   -----------------------------------------------------------------------
   Pools are ACTIVE if:
     • they have a pool_update ≤ cutoff (we take the latest via rn = 1),
     • and there is NO pool_retire with retiring_epoch ≤ cutoff.
   This filters out retired pools from *everything* downstream.
-------------------------------------------------------------------------*/
ActivePoolsAtCutoff AS (
  SELECT
    rpu.gov_action_id,
    rpu.pool_hash_id
  FROM RankedPoolUpdates rpu
  LEFT JOIN pool_retire pr
    ON pr.hash_id = rpu.pool_hash_id
   AND pr.retiring_epoch <= rpu.cutoff_epoch
  WHERE rpu.rn = 1          -- latest update at/before cutoff
    AND pr.id IS NULL       -- not retired by cutoff
),

/* -----------------------------------------------------------------------
   RankedPoolVotes
   -----------------------------------------------------------------------
   Latest explicit SPO vote per (pool, proposal). We don’t yet restrict
   to active pools here (we do that where it matters: counting and totals).
-------------------------------------------------------------------------*/
RankedPoolVotes AS (
  SELECT
      vp.*,
      ROW_NUMBER() OVER (
        PARTITION BY vp.pool_voter, vp.gov_action_proposal_id 
        ORDER BY vp.tx_id DESC
      ) AS rn
  FROM voting_procedure vp
  JOIN TargetAction ta 
    ON vp.gov_action_proposal_id = ta.id
  WHERE vp.pool_voter IS NOT NULL
),

/* -----------------------------------------------------------------------
   PoolsWithVote
   -----------------------------------------------------------------------
   The set of (action, pool) that DID cast a vote (latest per pool/action),
   intersected with ACTIVE pools. Used to:
     • compute “voting power of pools that voted”
     • exclude voters from the “auto” diagnostics buckets
-------------------------------------------------------------------------*/
PoolsWithVote AS (
  SELECT DISTINCT
    rpv.gov_action_proposal_id AS gov_action_id,
    rpv.pool_voter            AS pool_hash_id
  FROM RankedPoolVotes rpv
  JOIN ActivePoolsAtCutoff ap
    ON ap.gov_action_id = rpv.gov_action_proposal_id
   AND ap.pool_hash_id  = rpv.pool_voter
  WHERE rpv.rn = 1
),

/* -----------------------------------------------------------------------
   PoolVotes
   -----------------------------------------------------------------------
   Weighted explicit SPO votes per action, summing the pool voting_power
   snapshot determined at cutoff (RankedPoolStats rn=1). Restricted to
   ACTIVE pools only.
-------------------------------------------------------------------------*/
PoolVotes AS (
  SELECT
      rpv.gov_action_proposal_id,
      SUM(CASE WHEN rpv.vote = 'Yes'     THEN rps.voting_power ELSE 0 END) AS pool_yes_votes,
      SUM(CASE WHEN rpv.vote = 'No'      THEN rps.voting_power ELSE 0 END) AS pool_no_votes,
      SUM(CASE WHEN rpv.vote = 'Abstain' THEN rps.voting_power ELSE 0 END) AS pool_abstain_votes
  FROM RankedPoolVotes rpv
  JOIN RankedPoolStats rps
    ON rpv.pool_voter = rps.pool_hash_id
   AND rpv.gov_action_proposal_id = rps.action_id
   AND rps.rn = 1
  JOIN ActivePoolsAtCutoff ap
    ON ap.gov_action_id = rps.action_id
   AND ap.pool_hash_id  = rps.pool_hash_id
  WHERE rpv.rn = 1
  GROUP BY rpv.gov_action_proposal_id
),

/* -----------------------------------------------------------------------
   TotalStakeControlledByStakePools
   -----------------------------------------------------------------------
   For each action, sum the voting_power (snapshot at cutoff) across all
   ACTIVE pools. This is the “s” term in the ledger formula yes / (s - a).
-------------------------------------------------------------------------*/
TotalStakeControlledByStakePools AS (
  SELECT
      rps.action_id AS gov_action_id,
      COALESCE(SUM(rps.voting_power), 0)::bigint AS total
  FROM RankedPoolStats rps
  JOIN ActivePoolsAtCutoff ap
    ON ap.gov_action_id = rps.action_id
   AND ap.pool_hash_id  = rps.pool_hash_id
  WHERE rps.rn = 1
  GROUP BY rps.action_id
),

/* -----------------------------------------------------------------------
   VotingPowerOfPoolsThatVoted
   -----------------------------------------------------------------------
   Sum of voting_power for ACTIVE pools that cast an explicit vote.
   Used to compute spo_not_voted_voting_power as (total - voted).
-------------------------------------------------------------------------*/
VotingPowerOfPoolsThatVoted AS (
  SELECT
      rps.action_id AS gov_action_id,
      COALESCE(SUM(rps.voting_power), 0)::bigint AS total
  FROM RankedPoolStats rps
  JOIN ActivePoolsAtCutoff ap
    ON ap.gov_action_id = rps.action_id
   AND ap.pool_hash_id  = rps.pool_hash_id
  JOIN PoolsWithVote pwv
    ON pwv.gov_action_id = rps.action_id
   AND pwv.pool_hash_id  = rps.pool_hash_id
  WHERE rps.rn = 1
  GROUP BY rps.action_id
),

/* -----------------------------------------------------------------------
   RewardAddrAtCutoff
   -----------------------------------------------------------------------
   For each ACTIVE pool/action, fetch the reward address id that was in
   force at/before cutoff. This is the address whose DRep delegation we
   consult to decide “auto” behavior for non-voters.
-------------------------------------------------------------------------*/
RewardAddrAtCutoff AS (
  SELECT rpu.gov_action_id, rpu.pool_hash_id, rpu.reward_addr_id
  FROM RankedPoolUpdates rpu
  JOIN ActivePoolsAtCutoff ap
    ON ap.gov_action_id = rpu.gov_action_id
   AND ap.pool_hash_id  = rpu.pool_hash_id
  WHERE rpu.rn = 1
),

/* -----------------------------------------------------------------------
   LatestRewardAddrDRep
   -----------------------------------------------------------------------
   For each ACTIVE pool/action, find the reward address’ latest
   delegation_vote to a DRep at/before cutoff. DISTINCT ON picks the most
   recent (by epoch_no DESC, then tx_id DESC).
   We only need the DRep “view” (its name); we compare to the two special
   ones: 'drep_always_abstain' and 'drep_always_no_confidence'.
-------------------------------------------------------------------------*/
LatestRewardAddrDRep AS (
  SELECT DISTINCT ON (rac.gov_action_id, rac.pool_hash_id)
    rac.gov_action_id,
    rac.pool_hash_id,
    dh.view AS drep_view
  FROM RewardAddrAtCutoff rac
  JOIN delegation_vote dv ON dv.addr_id = rac.reward_addr_id
  JOIN tx dtx   ON dtx.id = dv.tx_id
  JOIN block db ON db.id = dtx.block_id
  JOIN drep_hash dh ON dh.id = dv.drep_hash_id
  JOIN ActionEpoch ae ON ae.id = rac.gov_action_id
  WHERE db.epoch_no <= ae.cutoff_epoch
  ORDER BY rac.gov_action_id, rac.pool_hash_id, db.epoch_no DESC, dtx.id DESC
),

/* -----------------------------------------------------------------------
   PoolRewardAddrSpecial
   -----------------------------------------------------------------------
   Classify pools based on the reward address’ special DRep (if any).
   We mark booleans for the two special cases.
-------------------------------------------------------------------------*/
PoolRewardAddrSpecial AS (
  SELECT
    gov_action_id,
    pool_hash_id,
    (drep_view = 'drep_always_abstain')        AS is_auto_abstain,
    (drep_view = 'drep_always_no_confidence')  AS is_auto_noconf
  FROM LatestRewardAddrDRep
),

/* -----------------------------------------------------------------------
   SPOAutoAbstainVotingPower  (Diagnostics)
   -----------------------------------------------------------------------
   Auto-abstain power is the sum of ACTIVE pool voting power for pools
   whose reward address delegates to AlwaysAbstain AND that did NOT cast
   an explicit vote. This is folded into Abstain in the effective ratio.
-------------------------------------------------------------------------*/
SPOAutoAbstainVotingPower AS (
  SELECT
    pras.gov_action_id,
    COALESCE(SUM(rps.voting_power), 0)::bigint AS total
  FROM PoolRewardAddrSpecial pras
  JOIN ActivePoolsAtCutoff ap
    ON ap.gov_action_id = pras.gov_action_id
   AND ap.pool_hash_id  = pras.pool_hash_id
  JOIN RankedPoolStats rps
    ON rps.action_id = pras.gov_action_id
   AND rps.pool_hash_id = pras.pool_hash_id
   AND rps.rn = 1
  LEFT JOIN PoolsWithVote pwv
    ON pwv.gov_action_id = pras.gov_action_id
   AND pwv.pool_hash_id  = pras.pool_hash_id
  WHERE pras.is_auto_abstain
    AND pwv.pool_hash_id IS NULL   -- EXCLUDE pools that voted
  GROUP BY pras.gov_action_id
),

/* -----------------------------------------------------------------------
   SPONoConfidenceVotingPower  (Diagnostics)
   -----------------------------------------------------------------------
   Auto-no-confidence power is the sum of ACTIVE pool voting power for
   pools whose reward address delegates to AlwaysNoConfidence AND that did
   NOT cast an explicit vote. For NewCommittee, this remains “No” in
   ledger folding (i.e., not added to Yes).
-------------------------------------------------------------------------*/
SPONoConfidenceVotingPower AS (
  SELECT
    pras.gov_action_id,
    COALESCE(SUM(rps.voting_power), 0)::bigint AS total
  FROM PoolRewardAddrSpecial pras
  JOIN ActivePoolsAtCutoff ap
    ON ap.gov_action_id = pras.gov_action_id
   AND ap.pool_hash_id  = pras.pool_hash_id
  JOIN RankedPoolStats rps
    ON rps.action_id = pras.gov_action_id
   AND rps.pool_hash_id = pras.pool_hash_id
   AND rps.rn = 1
  LEFT JOIN PoolsWithVote pwv
    ON pwv.gov_action_id = pras.gov_action_id
   AND pwv.pool_hash_id  = pras.pool_hash_id
  WHERE pras.is_auto_noconf
    AND pwv.pool_hash_id IS NULL   -- EXCLUDE pools that voted
  GROUP BY pras.gov_action_id
),

/* -----------------------------------------------------------------------
   EffectiveAbstain (Ledger folding, non-bootstrap, NewCommittee)
   -----------------------------------------------------------------------
   Effective abstain = explicit Abstain + auto-abstain (non-voters whose
   reward address delegates to AlwaysAbstain).
   In the ledger ratio: denominator = total - effective_abstain.
-------------------------------------------------------------------------*/
EffectiveAbstain AS (
  SELECT
    ta.id AS gov_action_id,
    (COALESCE(pv.pool_abstain_votes,0) + COALESCE(spo_abs.total,0))::bigint AS abstain_power_effective
  FROM TargetAction ta
  LEFT JOIN PoolVotes pv ON pv.gov_action_proposal_id = ta.id
  LEFT JOIN SPOAutoAbstainVotingPower spo_abs ON spo_abs.gov_action_id = ta.id
),

/* -----------------------------------------------------------------------
   EffectiveYes (Ledger folding, non-bootstrap, NewCommittee)
   -----------------------------------------------------------------------
   Effective yes = explicit Yes only, for NewCommittee (no auto→Yes folding).
   (Auto-NoConfidence contributes to Yes only for NoConfidence actions.)
-------------------------------------------------------------------------*/
EffectiveYes AS (
  SELECT
    ta.id AS gov_action_id,
    COALESCE(pv.pool_yes_votes,0)::bigint AS yes_power_effective
  FROM TargetAction ta
  LEFT JOIN PoolVotes pv ON pv.gov_action_proposal_id = ta.id
)

-- ======================================================================
-- Final SELECT: one row per NewCommittee action with raw and effective metrics
-- ======================================================================
SELECT
  ta.id AS gov_action_id,
  encode(t.hash, 'hex') AS tx_hash,
  ta.index AS action_index,
  ta.type::text AS action_type,

  -- Raw explicit weighted SPO votes (ACTIVE pools only)
  COALESCE(pv.pool_yes_votes, 0)     AS pool_yes_votes,
  COALESCE(pv.pool_no_votes, 0)      AS pool_no_votes,
  COALESCE(pv.pool_abstain_votes, 0) AS pool_abstain_votes,

  -- Totals & diagnostics (ACTIVE pools only)
  COALESCE(tsp.total, 0)                                 AS total_stake_controlled_by_stake_pools,  -- 's' in yes/(s-a)
  COALESCE(vpv.total, 0)                                 AS voting_power_of_pools_that_voted,
  (COALESCE(tsp.total, 0) - COALESCE(vpv.total, 0))::bigint AS spo_not_voted_voting_power,          -- diagnostic
  COALESCE(spo_abs.total, 0)                             AS spo_auto_abstain_voting_power,          -- diagnostic (folds into abstain)
  COALESCE(spo_noc.total, 0)                             AS spo_no_confidence_voting_power,         -- diagnostic (stays "No" for NewCommittee)

  -- Ledger-style effective folding (non-bootstrap; NewCommittee):
  eYes.yes_power_effective                               AS spo_yes_power_effective,                -- 'y' in yes/(s-a)
  eAbst.abstain_power_effective                          AS spo_abstain_power_effective,            -- 'a' in yes/(s-a)
  GREATEST(COALESCE(tsp.total,0) - eAbst.abstain_power_effective, 0)::bigint AS spo_denominator_effective,
  CASE
    WHEN GREATEST(COALESCE(tsp.total,0) - eAbst.abstain_power_effective, 0) = 0
      THEN 0::numeric
      ELSE
        ROUND(
          (eYes.yes_power_effective::numeric
          / NULLIF((COALESCE(tsp.total,0) - eAbst.abstain_power_effective)::numeric, 0)
          ) * 100, 4
        )
  END AS spo_yes_ratio_pct_effective

FROM TargetAction ta
JOIN tx t ON t.id = ta.tx_id
LEFT JOIN PoolVotes pv
  ON pv.gov_action_proposal_id = ta.id
LEFT JOIN TotalStakeControlledByStakePools tsp
  ON tsp.gov_action_id = ta.id
LEFT JOIN VotingPowerOfPoolsThatVoted vpv
  ON vpv.gov_action_id = ta.id
LEFT JOIN SPOAutoAbstainVotingPower spo_abs
  ON spo_abs.gov_action_id = ta.id
LEFT JOIN SPONoConfidenceVotingPower spo_noc
  ON spo_noc.gov_action_id = ta.id
LEFT JOIN EffectiveAbstain eAbst
  ON eAbst.gov_action_id = ta.id
LEFT JOIN EffectiveYes eYes
  ON eYes.gov_action_id = ta.id;
