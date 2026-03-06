#!/usr/bin/env bash
set -euo pipefail

# report_dr_status.sh
# Posts DR run status to Slack and prints a short summary for CI logs.
# Usage: ./scripts/ci/report_dr_status.sh --status=success --rto=45m --rpo=15m --log=/tmp/dr.log

usage(){
  cat <<EOF
Usage: --status=(success|failure) --rto=45m --rpo=15m --log=/path/to/log
Environment:
  SECRET_PROJECT - optional GCP project to fetch slack-webhook secret
  SLACK_WEBHOOK  - direct webhook URL (preferred: set via CI variable)
EOF
}

STATUS=""
RTO=""
RPO=""
LOGFILE=""

for arg in "$@"; do
  case "$arg" in
    --status=*) STATUS=${arg#*=} ;;
    --rto=*) RTO=${arg#*=} ;;
    --rpo=*) RPO=${arg#*=} ;;
    --log=*) LOGFILE=${arg#*=} ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $arg"; usage; exit 2 ;;
  esac
done

if [[ -z "$SLACK_WEBHOOK" && -n "${SECRET_PROJECT:-}" && command -v gcloud >/dev/null 2>&1 ]]; then
  SLACK_WEBHOOK=$(gcloud secrets versions access latest --secret=slack-webhook --project=$SECRET_PROJECT || true)
fi

if [[ -z "$SLACK_WEBHOOK" ]]; then
  echo "No SLACK_WEBHOOK set; will print summary to stdout only" >&2
fi

SUMMARY="[DR] status=$STATUS; RTO=$RTO; RPO=$RPO; log=${LOGFILE:-none}"

echo "$SUMMARY"

if [[ -n "$SLACK_WEBHOOK" ]]; then
  curl -s -X POST -H 'Content-type: application/json' --data "{\"text\": \"$SUMMARY\"}" "$SLACK_WEBHOOK" >/dev/null || true
  echo "Posted summary to Slack." 
fi

exit 0
