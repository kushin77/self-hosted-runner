#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-${CI_PROJECT_ID:-}}"
API_URL="${GITLAB_API_URL:-https://gitlab.com/api/v4}"
TOKEN="${GITLAB_TOKEN:-}" 

if [ -z "$PROJECT_ID" ]; then
  echo "Usage: PROJECT_ID or CI_PROJECT_ID must be set"
  exit 1
fi

if [ -z "$TOKEN" ]; then
  echo "Usage: GITLAB_TOKEN must be set (API token with 'api' scope)"
  exit 1
fi

labels=(
  "state:backlog:#8b949e"
  "state:in-progress:#0366d6"
  "state:review:#6f42c1"
  "state:blocked:#d73a49"
  "state:done:#0e8a16"
  "type:bug:#d73a49"
  "type:feature:#a2eeef"
  "type:security:#b60205"
  "type:compliance:#ff7f0e"
  "priority:p0:#b60205"
  "priority:p1:#d876e3"
  "priority:p2:#f9d0c4"
)

echo "Creating/updating labels in project $PROJECT_ID..."

existing=$(curl -sSL -H "PRIVATE-TOKEN: $TOKEN" "$API_URL/projects/$PROJECT_ID/labels?per_page=200" )

for entry in "${labels[@]}"; do
  name=${entry%%:*}
  rest=${entry#*:}
  color="#${rest##*:}"

  # For names containing :, GitLab label names allow ':' so use full name
  label_name="$name"

  if echo "$existing" | jq -r '.[].name' 2>/dev/null | grep -xF -- "$label_name" >/dev/null 2>&1; then
    echo "  ✓ Label exists: $label_name — updating color to $color"
    curl -sSL -X PUT -H "PRIVATE-TOKEN: $TOKEN" -H "Content-Type: application/json" \
      "$API_URL/projects/$PROJECT_ID/labels?name=$(printf '%s' "$label_name" | jq -sRr @uri)" \
      -d "{\"color\": \"$color\"}" >/dev/null || true
  else
    echo "  + Creating label: $label_name ($color)"
    curl -sSL -X POST -H "PRIVATE-TOKEN: $TOKEN" -H "Content-Type: application/json" \
      "$API_URL/projects/$PROJECT_ID/labels" \
      -d "{\"name\": \"$label_name\", \"color\": \"$color\"}" >/dev/null || true
  fi
done

echo "Done."
