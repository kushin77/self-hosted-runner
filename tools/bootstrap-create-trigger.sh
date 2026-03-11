#!/usr/bin/env bash
set -euo pipefail

PROJECT=$(gcloud config get-value project 2>/dev/null || true)
ACTIVE_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null || echo "UNKNOWN")
TRIGGER_NAME="gov-scan-trigger"
BUILD_CONFIG="governance/cloudbuild-gov-scan.yaml"
LOGFILE="governance/trigger-creation-log.txt"
ISSUE_AUDIT=2619
ISSUE_TRACK=2623

timestamp() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

echo "$(timestamp) | starting trigger bootstrap | account=$ACTIVE_ACCOUNT | project=$PROJECT" >> "$LOGFILE"

exists() {
  gcloud beta builds triggers list --project="$PROJECT" --format=json 2>/dev/null | jq -e ".[] | select(.name==\"$TRIGGER_NAME\")" >/dev/null 2>&1
}

post_github() {
  # args: issue_number, body
  if [ -z "${GITHUB_TOKEN:-}" ]; then
    echo "$(timestamp) | no GITHUB_TOKEN; skipping GitHub comment" >> "$LOGFILE"
    return 0
  fi
  local issue=$1; shift
  local body=$1
  curl -sS -X POST -H "Authorization: token $GITHUB_TOKEN" -H "Content-Type: application/json" \
    "https://api.github.com/repos/kushin77/self-hosted-runner/issues/$issue/comments" \
    -d "$(jq -Rn --arg b "$body" '{body:$b}')" >/dev/null 2>&1 || true
}

if exists; then
  echo "$(timestamp) | trigger exists; nothing to do" >> "$LOGFILE"
  exit 0
fi

set +e
gcloud beta builds triggers create github \
  --name="$TRIGGER_NAME" \
  --repo-name="self-hosted-runner" \
  --repo-owner="kushin77" \
  --branch-pattern="^main$" \
  --build-config="$BUILD_CONFIG" \
  --description="Governance scanner (automatic scheduled runner)." --project="$PROJECT" 2>&1 | tee /tmp/gov-trigger-create.out
RC=$?
set -e

if [ $RC -ne 0 ]; then
  echo "$(timestamp) | trigger create FAILED (rc=$RC)" >> "$LOGFILE"
  echo "$(timestamp) | output: $(sed -n '1,200p' /tmp/gov-trigger-create.out | sed 's/"/\"/g')" >> "$LOGFILE"
  BODY="Attempted automated creation of Cloud Build trigger '$TRIGGER_NAME' but failed (rc=$RC). Active account: $ACTIVE_ACCOUNT. See governance/NEEDS_TRIGGER_CREATION.md for manual runbook."
  post_github $ISSUE_TRACK "$BODY"
  exit $RC
fi

# On success, run the trigger once to validate
set +e
RUN_OUT=$(gcloud beta builds triggers run "$TRIGGER_NAME" --branch=main --project="$PROJECT" 2>&1 || true)
RUN_RC=$?
set -e

echo "$(timestamp) | trigger created successfully by $ACTIVE_ACCOUNT" >> "$LOGFILE"
echo "$(timestamp) | first-run rc=$RUN_RC output: $(echo "$RUN_OUT" | tr '\n' ' ' | sed 's/"/\"/g')" >> "$LOGFILE"

if [ $RUN_RC -eq 0 ]; then
  BUILD_ID=$(echo "$RUN_OUT" | grep -oE "builds/[0-9]+" | head -n1 || true)
  echo "$(timestamp) | validated run build_id=$BUILD_ID" >> "$LOGFILE"
  BODY="Trigger '$TRIGGER_NAME' created and validated. First run: $BUILD_ID. Bootstrap executed by $ACTIVE_ACCOUNT on $PROJECT.\n\nLogs: governance/trigger-creation-log.txt"
  post_github $ISSUE_AUDIT "$BODY"
  post_github $ISSUE_TRACK "$BODY"
else
  BODY="Trigger '$TRIGGER_NAME' created but first run returned rc=$RUN_RC. Check Cloud Build logs. Bootstrap executed by $ACTIVE_ACCOUNT on $PROJECT.\n\nLogs: governance/trigger-creation-log.txt"
  post_github $ISSUE_TRACK "$BODY"
  exit 2
fi

echo "$(timestamp) | bootstrap completed" >> "$LOGFILE"
