#!/bin/bash
# Create required labels in a portable way (avoids associative arrays)

set -e

REPO="${1:?Usage: create-required-labels.sh <owner/repo>}"
GH_REPO="--repo $REPO"

required=(
  "state:backlog"
  "state:in-progress"
  "state:review"
  "state:blocked"
  "state:done"
  "type:bug"
  "type:feature"
  "type:security"
  "type:compliance"
  "priority:p0"
  "priority:p1"
  "priority:p2"
)

colors=(
  "e2e2e2"
  "0075ca"
  "9900ff"
  "ff0000"
  "28a745"
  "d73a4a"
  "a2eeef"
  "ff0000"
  "d73a49"
  "ff0000"
  "ff5722"
  "ffc107"
)

descriptions=(
  "Issue in backlog, not yet started"
  "Someone is actively working on this"
  "PR submitted, awaiting review"
  "Blocked by other issue(s)"
  "Complete, pending release"
  "Something isn't working"
  "New feature or enhancement"
  "Security vulnerability"
  "Compliance or audit requirement"
  "Critical priority - 12 hour SLA"
  "High priority - 3 day SLA"
  "Medium priority - 7 day SLA"
)

echo "Creating required labels in $REPO..."

for i in "${!required[@]}"; do
  label="${required[$i]}"
  color="${colors[$i]}"
  desc="${descriptions[$i]}"

  # Use --force to update if exists
  gh label create "$label" $GH_REPO --color "$color" --description "$desc" 2>/dev/null || \
    gh label edit "$label" $GH_REPO --color "$color" --description "$desc" || true
  echo "  ✓ $label"
done

echo "Done creating required labels."
