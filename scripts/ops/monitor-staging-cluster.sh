#!/usr/bin/env bash
set -euo pipefail

# Monitor staging cluster connectivity and trigger smoke-test when ready
# Usage: bash scripts/ops/monitor-staging-cluster.sh [max_attempts]

CLUSTER_HOST="192.168.168.42"
CLUSTER_PORT="6443"
MAX_ATTEMPTS="${1:-120}"  # ~60 min at 30s intervals
CHECK_INTERVAL=30
ATTEMPT=0

echo "[$(date +'%Y-%m-%dT%H:%M:%SZ')] Starting cluster monitoring..."
echo "Target: $CLUSTER_HOST:$CLUSTER_PORT"
echo "Max attempts: $MAX_ATTEMPTS (Est. $((MAX_ATTEMPTS * CHECK_INTERVAL / 60)) min)"

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
  ATTEMPT=$((ATTEMPT + 1))
  
  if nc -z "$CLUSTER_HOST" "$CLUSTER_PORT" 2>/dev/null; then
    echo ""
    echo "✅ [$(date +'%Y-%m-%dT%H:%M:%SZ')] CLUSTER ONLINE! (Attempt $ATTEMPT)"
    echo "TCP connectivity to $CLUSTER_HOST:$CLUSTER_PORT restored"
    echo ""
    
    # Post update to issue #343
    gh issue comment 343 --body "✅ **Cluster recovered** at $(date +'%Y-%m-%dT%H:%M:%SZ')

Connectivity to 192.168.168.42:6443 restored.

**Next steps**:
1. Eng: Run smoke-test: \`bash scripts/ci/run-keda-smoke-test.sh\`
2. Ops: Monitor test execution in Actions
3. Eng: Sign off #326 once smoke-test passes" || true
    
    break
  else
    printf "."
    sleep "$CHECK_INTERVAL"
  fi
  
  # Every 10 attempts (5 min), print a progress message
  if [ $((ATTEMPT % 10)) -eq 0 ]; then
    echo " [$ATTEMPT/$MAX_ATTEMPTS - $(date +'%H:%M:%SZ')]"
  fi
done

if [ $ATTEMPT -ge $MAX_ATTEMPTS ]; then
  echo ""
  echo "❌ [$(date +'%Y-%m-%dT%H:%M:%SZ')] TIMEOUT - Cluster still offline after $MAX_ATTEMPTS checks"
  echo ""
  
  # Post escalation to issue #343
  gh issue comment 343 --body "⚠️ **Escalation**: Cluster still offline after $(($MAX_ATTEMPTS * $CHECK_INTERVAL / 60)) minutes

Automatic monitoring timed out. Manual intervention required.

**Action items**:
1. Check SSH access to 192.168.168.42
2. Verify K3s systemd unit: \`systemctl status k3s\`
3. Check firewall rules for port 6443
4. Review recent system logs" || true
  
  exit 1
fi

echo ""
echo "✅ Monitor complete. Cluster is online. Ready for smoke-test."
