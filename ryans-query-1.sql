/* =======================================================================
   SPO voting (ledger-style) for NewCommittee actions (non-bootstrap)
   -----------------------------------------------------------------------
   VERSION: This version does NOT filter out retired pools.
   That means:
     • Pools that submitted a retire certificate (pool_retire.retiring_epoch ≤ cutoff)
       could still be included in voting power, totals, or auto diagnostics.
     • This can inflate stake values and distort ledger alignment.

   The rest is identical to the "with retired filter" version:
     • Only NewCommittee proposals.
     • Epoch cutoff logic (per action).
     • Dedup pool_stat.
     • Auto-Abstain/NoConfidence via reward address delegation.
     • Ledger-style folding (yes / (s - a)).

   ======================================================================= */

WITH
/* -----------------------------------------------------------------------
   EpochSelector
   -----------------------------------------------------------------------
   Toggle whether to run the query at a fixed epoch (e.g. 579)
   or at the latest epoch (MAX(no)).
   This is a global ceiling applied to each proposal’s “relevant epoch”.
-------------------------------------------------------------------------*/
EpochSelector AS (
  SELECT 579::integer AS selected_epoch            -- <<<<< FIXED: use epoch 579
  -- SELECT (SELECT MAX(no) FROM epoch) AS selected_epoch  -- <<<<< CURRENT: use latest epoch
),

/* -----------------------------------------------------------------------
   TargetAction
   -----------------------------------------------------------------------
   Restrict to proposals of type 'NewCommittee' (the db-sync enum).
   Each row represents one governance action we will report on.
-------------------------------------------------------------------------*/
TargetAction AS (
  SELECT 
      gap.id,         -- proposal id
      gap.tx_id,      -- creating tx id
      gap.index,      -- index within that tx
      gap.type        -- 'NewCommittee'
  FROM gov_action_proposal gap
  JOIN tx ON tx.id = gap.tx_id
  WHERE gap.type = 'NewCommittee'
),

/* -----------------------------------------------------------------------
   ActionEpoch
   -----------------------------------------------------------------------
   Compute the "cutoff epoch" for each proposal:
     relevant_epoch = earliest of ratified, expired, dropped, else MAX(no)
     cutoff_epoch   = LEAST(relevant_epoch, selected_epoch)
   This determines the snapshot point at which we evaluate pool votes and stake.
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
   pool_stat sometimes has multiple rows for the same pool in the same epoch.
   Deduplicate by keeping only the latest row per (pool, epoch).
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
   For each (pool, action), select the latest pool_stat row ≤ cutoff_epoch.
   rn=1 = row we keep.
   WARNING: Without filtering retired pools, this includes pools
   that may have retired before cutoff but still have pool_stat rows.
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
   The latest pool_update ≤ cutoff gives us the reward address.
   We use this later to check if the pool’s reward address delegates to
   AlwaysAbstain / AlwaysNoConfidence.
   WARNING: Again, retired pools can sneak in here because we don’t check
   pool_retire. So reward addresses for retired pools are still included.
-------------------------------------------------------------------------*/
RankedPoolUpdates AS (
  SELECT
    pu.id,
    ph.id        AS pool_hash_id,
    pu.reward_addr_id,
    ae.id        AS gov_action_id,
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
   RankedPoolVotes
   -----------------------------------------------------------------------
   Latest explicit vote per pool/proposal (Yes/No/Abstain).
   rn=1 ensures we only keep the most recent.
   WARNING: If a retired pool cast a vote, it will be included here.
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
   Set of pools that cast a vote for an action.
   Used to:
     - measure power of pools that voted,
     - exclude those pools from "auto" buckets.
   WARNING: Includes retired pools since we do not filter them out.
-------------------------------------------------------------------------*/
PoolsWithVote AS (
  SELECT DISTINCT
    rpv.gov_action_proposal_id AS gov_action_id,
    rpv.pool_voter            AS pool_hash_id
  FROM RankedPoolVotes rpv
  WHERE rpv.rn = 1
),

/* -----------------------------------------------------------------------
   PoolVotes
   -----------------------------------------------------------------------
   Weighted Yes/No/Abstain power of pools that voted.
   Joins RankedPoolStats to get the pool voting_power at cutoff.
   WARNING: Includes retired pools (if they have pool_stat rows).
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
  WHERE rpv.rn = 1
  GROUP BY rpv.gov_action_proposal_id
),

/* -----------------------------------------------------------------------
   TotalStakeControlledByStakePools
   -----------------------------------------------------------------------
   Sum of voting_power of all pools (active or retired!) at cutoff.
   WARNING: Retired pools are included because no retire check is applied.
-------------------------------------------------------------------------*/
TotalStakeControlledByStakePools AS (
  SELECT
      rps.action_id AS gov_action_id,
      COALESCE(SUM(rps.voting_power), 0)::bigint AS total
  FROM RankedPoolStats rps
  WHERE rps.rn = 1
  GROUP BY rps.action_id
),

/* -----------------------------------------------------------------------
   VotingPowerOfPoolsThatVoted
   -----------------------------------------------------------------------
   Sum of voting_power for pools that voted.
   WARNING: Retired pools can still be counted if they voted.
-------------------------------------------------------------------------*/
VotingPowerOfPoolsThatVoted AS (
  SELECT
      rps.action_id AS gov_action_id,
      COALESCE(SUM(rps.voting_power), 0)::bigint AS total
  FROM RankedPoolStats rps
  JOIN PoolsWithVote pwv
    ON pwv.gov_action_id = rps.action_id
   AND pwv.pool_hash_id  = rps.pool_hash_id
  WHERE rps.rn = 1
  GROUP BY rps.action_id
),

/* -----------------------------------------------------------------------
   RewardAddrAtCutoff
   -----------------------------------------------------------------------
   Get each pool’s reward address at cutoff (for auto delegation check).
   WARNING: Retired pools still appear here.
-------------------------------------------------------------------------*/
RewardAddrAtCutoff AS (
  SELECT rpu.gov_action_id, rpu.pool_hash_id, rpu.reward_addr_id
  FROM RankedPoolUpdates rpu
  WHERE rpu.rn = 1
),

/* -----------------------------------------------------------------------
   LatestRewardAddrDRep
   -----------------------------------------------------------------------
   For each pool, find the reward address’ latest delegation to a DRep ≤ cutoff.
   Used to detect auto-abstain / auto-no-confidence.
   WARNING: Retired pools still included.
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
   Classify each pool (including retired ones!) by whether its reward address
   delegates to AlwaysAbstain or AlwaysNoConfidence.
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
   SPOAutoAbstainVotingPower
   -----------------------------------------------------------------------
   Non-voting pools whose reward addr delegates to AlwaysAbstain.
   Folded into Abstain in ledger-style effective calculation.
   WARNING: Retired pools not excluded, so their stake may inflate this bucket.
-------------------------------------------------------------------------*/
SPOAutoAbstainVotingPower AS (
  SELECT
    pras.gov_action_id,
    COALESCE(SUM(rps.voting_power), 0)::bigint AS total
  FROM PoolRewardAddrSpecial pras
  JOIN RankedPoolStats rps
    ON rps.action_id = pras.gov_action_id
   AND rps.pool_hash_id = pras.pool_hash_id
   AND rps.rn = 1
  LEFT JOIN PoolsWithVote pwv
    ON pwv.gov_action_id = pras.gov_action_id
   AND pwv.pool_hash_id  = pras.pool_hash_id
  WHERE pras.is_auto_abstain
    AND pwv.pool_hash_id IS NULL
  GROUP BY pras.gov_action_id
),

/* -----------------------------------------------------------------------
   SPONoConfidenceVotingPower
   -----------------------------------------------------------------------
   Non-voting pools whose reward addr delegates to AlwaysNoConfidence.
   For NewCommittee, this does NOT add to Yes; it remains No.
   WARNING: Retired pools not excluded, so may inflate this bucket.
-------------------------------------------------------------------------*/
SPONoConfidenceVotingPower AS (
  SELECT
    pras.gov_action_id,
    COALESCE(SUM(rps.voting_power), 0)::bigint AS total
  FROM PoolRewardAddrSpecial pras
  JOIN RankedPoolStats rps
    ON rps.action_id = pras.gov_action_id
   AND rps.pool_hash_id = pras.pool_hash_id
   AND rps.rn = 1
  LEFT JOIN PoolsWithVote pwv
    ON pwv.gov_action_id = pras.gov_action_id
   AND pwv.pool_hash_id  = pras.pool_hash_id
  WHERE pras.is_auto_noconf
    AND pwv.pool_hash_id IS NULL
  GROUP BY pras.gov_action_id
),

/* -----------------------------------------------------------------------
   EffectiveAbstain
   -----------------------------------------------------------------------
   Ledger-style abstain = explicit Abstain + auto-abstain.
   WARNING: Retired pools still included if they fall in either category.
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
   EffectiveYes
   -----------------------------------------------------------------------
   Ledger-style yes = explicit Yes only (for NewCommittee).
   WARNING: Retired pools still included in explicit Yes votes.
-------------------------------------------------------------------------*/
EffectiveYes AS (
  SELECT
    ta.id AS gov_action_id,
    COALESCE(pv.pool_yes_votes,0)::bigint AS yes_power_effective
  FROM TargetAction ta
  LEFT JOIN PoolVotes pv ON pv.gov_action_proposal_id = ta.id
)

-- ======================================================================
-- Final output
-- ======================================================================
SELECT
  ta.id AS gov_action_id,
  encode(t.hash, 'hex') AS tx_hash,
  ta.index AS action_index,
  ta.type::text AS action_type,

  -- Raw explicit weighted votes
  COALESCE(pv.pool_yes_votes, 0)     AS pool_yes_votes,
  COALESCE(pv.pool_no_votes, 0)      AS pool_no_votes,
  COALESCE(pv.pool_abstain_votes, 0) AS pool_abstain_votes,

  -- Totals & diagnostics
  COALESCE(tsp.total, 0)                                 AS total_stake_controlled_by_stake_pools,
  COALESCE(vpv.total, 0)                                 AS voting_power_of_pools_that_voted,
  (COALESCE(tsp.total, 0) - COALESCE(vpv.total, 0))::bigint AS spo_not_voted_voting_power,
  COALESCE(spo_abs.total, 0)                             AS spo_auto_abstain_voting_power,
  COALESCE(spo_noc.total, 0)                             AS spo_no_confidence_voting_power,

  -- Ledger-style folding
  eYes.yes_power_effective                               AS spo_yes_power_effective,
  eAbst.abstain_power_effective                          AS spo_abstain_power_effective,
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
