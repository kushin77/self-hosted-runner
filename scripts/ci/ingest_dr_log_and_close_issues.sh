#!/usr/bin/env bash
set -euo pipefail

# ingest_dr_log_and_close_issues.sh
# Usage: ./scripts/ci/ingest_dr_log_and_close_issues.sh /path/to/dr_dryrun.log
# This script extracts RTO/RPO from the log, appends a result summary to docs/DR_RUNBOOK.md,
# updates issues/905-run-live-dr-dryrun.md and issues/903-quarterly-dr-drill.md with the findings,
# and exits with non-zero if the log doesn't contain success markers.

LOGFILE=${1:-}
if [ -z "$LOGFILE" ] || [ ! -f "$LOGFILE" ]; then
  echo "Usage: $0 /path/to/dr_dryrun.log" >&2
  exit 2
fi

RTO=$(grep -Eo "RTO[: ]+[0-9]+m" "$LOGFILE" | head -n1 || true)
RPO=$(grep -Eo "RPO[: ]+[0-9]+m" "$LOGFILE" | head -n1 || true)
SUCCESS=$(grep -E "DR dry-run completed successfully|DR dry-run completed" "$LOGFILE" || true)

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

if [ -z "$SUCCESS" ]; then
  echo "Log does not show successful completion. Aborting update." >&2
  exit 3
fi

RTO=${RTO:-"RTO: unknown"}
RPO=${RPO:-"RPO: unknown"}

SUMMARY="- Date: ${TS}\n- Source log: ${LOGFILE}\n- Result: SUCCESS\n- ${RTO}\n- ${RPO}\n"

echo "Appending result to docs/DR_RUNBOOK.md"
echo "\nSimulated/Live run result:\n${SUMMARY}" >> docs/DR_RUNBOOK.md

echo "Updating issues/905-run-live-dr-dryrun.md"
awk -v summary="$SUMMARY" '
  BEGIN{p=1}
  /Checklist:/ && p==1 {print; print "\nRecent run result:"; print summary; p=0; next}
  {print}
' issues/905-run-live-dr-dryrun.md > /tmp/905.md && mv /tmp/905.md issues/905-run-live-dr-dryrun.md

echo "Updating issues/903-quarterly-dr-drill.md"
awk -v ts="$TS" -v rto="$RTO" -v rpo="$RPO" '
  BEGIN{added=0}
  /Recent activity:/ {print; print "- " ts ": Live DR dry-run completed. " rto ", " rpo ". See issues/905-run-live-dr-dryrun.md for logs."; added=1; next}
  {print}
  END{if(!added) print "\nRecent activity:\n- " ts ": Live DR dry-run completed. " rto ", " rpo ". See issues/905-run-live-dr-dryrun.md for logs."}
' issues/903-quarterly-dr-drill.md > /tmp/903.md && mv /tmp/903.md issues/903-quarterly-dr-drill.md

echo "Ingest complete. Please review changes and commit them." 
echo "Appended summary:\n${SUMMARY}"

exit 0
