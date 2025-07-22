#!/bin/bash

# Dependencies: curl, jq
API_BASE="https://api.koios.rest/api/v1"

# Step 1: Get the full proposal list
echo "Fetching proposal list from Koios..."
proposals=$(curl -s -X GET "$API_BASE/proposal_list" -H "accept: application/json")

# Step 2: Filter proposals without ratified/enacted/dropped/expired epochs
active_proposals=$(echo "$proposals" | jq -c '.[] | select(
  (.ratified_epoch == null) and
  (.enacted_epoch == null) and
  (.dropped_epoch == null) and
  (.expired_epoch == null)
) | {proposal_id}')

# Step 3: For each active proposal, fetch voting summary and collect data
echo "Fetching voting summaries for active proposals..."

results=()

while IFS= read -r proposal; do
  pid=$(echo "$proposal" | jq -r .proposal_id)
  summary=$(curl -s -X GET "$API_BASE/proposal_voting_summary?_proposal_id=$pid" -H "accept: application/json")

  if [[ $(echo "$summary" | jq 'length') -gt 0 ]]; then
    row=$(echo "$summary" | jq -r --arg id "$pid" '
      .[0] | {
        proposal_id: $id,
        drep_yes_pct,
        drep_no_pct,
        drep_abstain_votes_cast,
        drep_yes_votes_cast,
        drep_no_votes_cast
      }'
    )
    results+=("$row")
  fi
done <<< "$active_proposals"

# Step 4: Output sorted results by drep_yes_pct descending
echo -e "\nSorted Active Proposals by drep_yes_pct:"
printf '%s\n' "${results[@]}" | jq -s 'sort_by(.drep_yes_pct | tonumber) | reverse[]'
