#!/usr/bin/env bash
set -euo pipefail

# Triage open issues in a GitLab project: add backlog label, escalate security, assign owners
# Requires: PROJECT_ID or CI_PROJECT_ID, GITLAB_TOKEN

PROJECT_ID="${PROJECT_ID:-${CI_PROJECT_ID:-}}"
API_URL="${GITLAB_API_URL:-https://gitlab.com/api/v4}"
TOKEN="${GITLAB_TOKEN:-}"
DEFAULT_ASSIGNEE="${ASSIGNEE_USERNAME:-akushnir}"

if [ -z "$PROJECT_ID" ]; then
  echo "Usage: PROJECT_ID or CI_PROJECT_ID must be set"
  exit 1
fi

if [ -z "$TOKEN" ]; then
  echo "Usage: GITLAB_TOKEN must be set (API token with 'api' scope)"
  exit 1
fi

echo "🔍 Triaging issues for project $PROJECT_ID..."

# Resolve assignee id if provided
ASSIGNEE_ID=""
if [ -n "$DEFAULT_ASSIGNEE" ]; then
  user_res=$(curl -sSL -H "PRIVATE-TOKEN: $TOKEN" "$API_URL/users?username=$DEFAULT_ASSIGNEE")
  ASSIGNEE_ID=$(echo "$user_res" | jq -r '.[0].id // empty') || true
  if [ -n "$ASSIGNEE_ID" ]; then
    echo "  ✓ Resolved assignee '$DEFAULT_ASSIGNEE' -> id $ASSIGNEE_ID"
  else
    echo "  ⚠️ Could not resolve assignee username '$DEFAULT_ASSIGNEE'"
  fi
fi

page=1
per_page=100
declare -A counts
counts[total]=0
counts[labeled]=0
counts[backlog_added]=0
counts[security_escalated]=0

while :; do
  res=$(curl -sSL -H "PRIVATE-TOKEN: $TOKEN" "$API_URL/projects/$PROJECT_ID/issues?state=opened&per_page=$per_page&page=$page")
  issues_count=$(echo "$res" | jq 'length')
  if [ "$issues_count" -eq 0 ]; then
    break
  fi

  for i in $(seq 0 $((issues_count-1))); do
    issue_iid=$(echo "$res" | jq -r ".[$i].iid")
    title=$(echo "$res" | jq -r ".[$i].title")
    description=$(echo "$res" | jq -r ".[$i].description // empty")
    labels=$(echo "$res" | jq -r ".[$i].labels | join(",")")

    counts[total]=$((counts[total]+1))

    # If no labels, add state:backlog
    if [ -z "$labels" ] || [ "$labels" = "null" ]; then
      echo "  Adding labels to #$issue_iid..."
      new_labels="state:backlog"
      curl -sSL -X PUT -H "PRIVATE-TOKEN: $TOKEN" -H "Content-Type: application/json" \
        "$API_URL/projects/$PROJECT_ID/issues/$issue_iid" \
        -d "{\"labels\": \"$new_labels\"}" >/dev/null || true
      counts[backlog_added]=$((counts[backlog_added]+1))
      counts[labeled]=$((counts[labeled]+1))
    fi

    # Detect security keywords
    low_title=$(echo "$title" | tr '[:upper:]' '[:lower:]')
    low_desc=$(echo "$description" | tr '[:upper:]' '[:lower:]')
    if echo "$low_title $low_desc" | grep -E "security|vulnerability|vulnerable|cve|exploit" >/dev/null 2>&1 || echo ",${labels}," | grep -E ",type:security|,security," >/dev/null 2>&1; then
      echo "  Escalating security issue #$issue_iid"
      # add labels type:security and priority:p0 and assign
      updated_labels=$(echo "$labels" | awk -v l="type:security,priority:p0" 'BEGIN{FS=OFS=","} {if($0==""||$0=="null") print l; else print $0","l}')
      curl -sSL -X PUT -H "PRIVATE-TOKEN: $TOKEN" -H "Content-Type: application/json" \
        "$API_URL/projects/$PROJECT_ID/issues/$issue_iid" \
        -d "{\"labels\": \"$updated_labels\"}" >/dev/null || true

      if [ -n "$ASSIGNEE_ID" ]; then
        curl -sSL -X PUT -H "PRIVATE-TOKEN: $TOKEN" -H "Content-Type: application/json" \
          "$API_URL/projects/$PROJECT_ID/issues/$issue_iid" \
          -d "{\"assignee_ids\": [$ASSIGNEE_ID]}" >/dev/null || true
      fi

      counts[security_escalated]=$((counts[security_escalated]+1))
    fi
  done

  page=$((page+1))
done

echo "\n✅ Triage complete!"
echo "Summary:"
echo "  total: ${counts[total]}"
echo "  labeled: ${counts[labeled]}"
echo "  backlog_added: ${counts[backlog_added]}"
echo "  security_escalated: ${counts[security_escalated]}"

exit 0
