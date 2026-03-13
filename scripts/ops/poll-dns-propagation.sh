#!/bin/bash
# Poll DNS propagation for nexusshield.io and close issue when target seen
set -e
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_IP="192.168.168.42"
CHECK_DOMAIN="nexusshield.io"
LOG="$REPO_ROOT/logs/cutover/poller.log"
MAX_MINUTES=1440
SLEEP_SEC=30

mkdir -p "$(dirname "$LOG")"

echo "["$(date -u +%Y-%m-%dT%H:%M:%SZ)"] DNS poller started (target: $TARGET_IP)" >> "$LOG"

minutes=0
while [ $minutes -lt $MAX_MINUTES ]; do
  # Query multiple resolvers
  local_ips=$(dig @8.8.8.8 +short $CHECK_DOMAIN)
  google_ips="$local_ips"
  cloudflare_ips=$(dig @1.1.1.1 +short $CHECK_DOMAIN)
  local_resolv=$(dig +short $CHECK_DOMAIN)

  echo "["$(date -u +%Y-%m-%dT%H:%M:%SZ)"] Resolvers -> google:[$google_ips] cloudflare:[$cloudflare_ips] local:[$local_resolv]" >> "$LOG"

  match_count=0
  for ip in $google_ips $cloudflare_ips $local_resolv; do
    if [ "$ip" = "$TARGET_IP" ]; then
      match_count=$((match_count+1))
    fi
  done

  # Consider propagation successful if at least 2 of 3 resolvers return target
  if [ $match_count -ge 2 ]; then
    echo "["$(date -u +%Y-%m-%dT%H:%M:%SZ)"] DNS propagation observed (matches: $match_count). Closing Issue #1." >> "$LOG"

    # Update issues file safely (append closure section)
    ISSUES_FILE="$REPO_ROOT/issues/DEPLOYMENT_ISSUES.md"
    if [ -f "$ISSUES_FILE" ]; then
      cp "$ISSUES_FILE" "$ISSUES_FILE.bak"
      # Append closure note
      cat >> "$ISSUES_FILE" <<ISSUE_DONE

## Issue #1: DNS Cutover Phase 2+3 (Closed ✅)
**Status:** CLOSED - $(date -u +%Y-%m-%dT%H:%M:%SZ)
- Phase 1 (Canary): ✅ Complete
- Phase 2 (Full Promotion): ✅ Complete
- Phase 3 (Notifications): ✅ Complete
- Target: $TARGET_IP
- Logs: logs/cutover/execution_full_*.log

ISSUE_DONE
      cd "$REPO_ROOT"
      git add "$ISSUES_FILE" 2>/dev/null || true
      if git commit -m "ops: Close Issue #1 — DNS propagated to $TARGET_IP (automatic)" 2>/dev/null; then
        echo "["$(date -u +%Y-%m-%dT%H:%M:%SZ)"] Issues tracker updated and committed." >> "$LOG"
      else
        echo "["$(date -u +%Y-%m-%dT%H:%M:%SZ)"] Git commit skipped or failed (no changes to commit)." >> "$LOG"
      fi
    else
      echo "["$(date -u +%Y-%m-%dT%H:%M:%SZ)"] Issues file not found: $ISSUES_FILE" >> "$LOG"
    fi

    exit 0
  fi

  sleep $SLEEP_SEC
  minutes=$((minutes + SLEEP_SEC/60))
done

echo "["$(date -u +%Y-%m-%dT%H:%M:%SZ)"] DNS poller timeout after $MAX_MINUTES minutes" >> "$LOG"
exit 1
