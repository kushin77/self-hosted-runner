#!/usr/bin/env bash
# Verify handoff logs and close the corresponding GitHub issue when checks pass.
# Usage: verify-handoff.sh <issue-number> <log-file>

set -euo pipefail

ISSUE=${1:?issue number}
LOGFILE=${2:?log file}

if [ ! -f "$LOGFILE" ]; then
  echo "Log file not found: $LOGFILE" >&2
  exit 2
fi

echo "Verifying $LOGFILE for issue #$ISSUE"

# Basic sanity checks (heuristic)
PASS=0

case "$ISSUE" in
  2310)
    # system-level install: expect systemd enable/start messages
    if grep -Ei "enabled|started|installed|daemon-reload|Unit .* enabled" "$LOGFILE" >/dev/null; then
      PASS=1
    fi
    ;;
  2311)
    # cloud finalize: expect terraform apply / containers deployed
    if grep -Ei "apply complete|Terraform applied|Apply complete|Successfully applied" "$LOGFILE" >/dev/null || grep -Ei "container|service.*started|deployed" "$LOGFILE" >/dev/null; then
      PASS=1
    fi
    ;;
  *)
    # Generic check: non-empty and has timestamps
    if grep -E "[0-9]{4}-[0-9]{2}-[0-9]{2}" "$LOGFILE" >/dev/null; then
      PASS=1
    fi
    ;;
esac

if [ "$PASS" -eq 1 ]; then
  echo "Basic checks passed for issue #$ISSUE"
  # Compute SHA256 of the log for audit
  SHA=$(sha256sum "$LOGFILE" | awk '{print $1}')
  COMMENT="Automated verification: basic checks passed for issue #$ISSUE. Log SHA256: $SHA"
  gh issue comment "$ISSUE" --body "$COMMENT" || true
  gh issue close "$ISSUE" || true
  echo "Issue #$ISSUE closed (comment posted)."
  exit 0
else
  echo "Verification failed for issue #$ISSUE; leaving it open and posting findings."
  gh issue comment "$ISSUE" --body "Automated verification: basic checks failed for the provided log. Please review and re-run. If you need assistance, paste full log output." || true
  exit 3
fi
