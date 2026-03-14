#!/bin/bash

# 🚀 NAS STRESS TEST - QUICK DEPLOYMENT MONITOR
# Run this to check deployment progress
# Usage: bash monitor-nas-deployment.sh

set -e

WORKER="192.168.168.42"
AUTOMATION_USER="automation"
DEPLOYMENT_STATE_FILE="/var/lib/automation/.nas-stress-deployed"
RESULTS_DIR="/home/automation/nas-stress-results"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║         NAS STRESS TEST - DEPLOYMENT MONITOR              ║"
echo "║              Worker: $WORKER                               ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# ============================================================================
# SECTION 1: GIT & DEPLOYMENT STATUS
# ============================================================================
echo "📋 SECTION 1: GIT & DEPLOYMENT STATUS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo -n "  [1/5] Git commit on worker:        "
WORKER_COMMIT=$(ssh $AUTOMATION_USER@$WORKER "cd /home/akushnir/self-hosted-runner && git log -1 --oneline 2>/dev/null" 2>/dev/null || echo "CHECKING...")
if [[ $WORKER_COMMIT == *"3d4b61547"* ]]; then
  echo "✅ DEPLOYED (3d4b61547)"
else
  echo "⏳ PENDING... ($WORKER_COMMIT)"
fi

echo -n "  [2/5] Deployment state file:      "
DEPLOY_STATE=$(ssh $AUTOMATION_USER@$WORKER "cat $DEPLOYMENT_STATE_FILE 2>/dev/null" 2>/dev/null || echo "NOT_YET")
if [[ "$DEPLOY_STATE" == *"DEPLOYED"* ]]; then
  echo "✅ DEPLOYED"
elif [[ "$DEPLOY_STATE" == "NOT_YET" ]]; then
  echo "⏳ PENDING..."
else
  echo "📊 $DEPLOY_STATE"
fi

echo -n "  [3/5] Auto-deploy service:        "
AUTODEPLOY_ACTIVITY=$(ssh $AUTOMATION_USER@$WORKER "sudo journalctl -u nexusshield-auto-deploy.service -n 5 --no-pager 2>/dev/null | grep -i 'nas\|deployed' | wc -l" 2>/dev/null || echo "0")
if [[ $AUTODEPLOY_ACTIVITY -gt 0 ]]; then
  echo "✅ DETECTED NAS CHANGES"
else
  echo "⏳ POLLING... (check in 5-10 min)"
fi

echo ""

# ============================================================================
# SECTION 2: SYSTEMD STATUS
# ============================================================================
echo "🔧 SECTION 2: SYSTEMD SERVICES & TIMERS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "  Checking systemd timers..."
TIMERS=$(ssh $AUTOMATION_USER@$WORKER "sudo systemctl list-timers nas-stress-test*.timer --no-pager 2>/dev/null" 2>/dev/null | tail -3)
if [[ ! -z "$TIMERS" ]]; then
  echo "  ✅ Systemd services installed:"
  echo "$TIMERS" | while IFS= read -r line; do
    echo "     $line"
  done
else
  echo "  ⏳ Systemd services not yet installed (pending auto-deploy)"
fi

echo ""

# ============================================================================
# SECTION 3: TEST RESULTS
# ============================================================================
echo "📊 SECTION 3: TEST RESULTS & MONITORING"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "  Checking results directory: $RESULTS_DIR"
RESULTS_COUNT=$(ssh $AUTOMATION_USER@$WORKER "ls -1 $RESULTS_DIR/*.json 2>/dev/null | wc -l" 2>/dev/null || echo "0")
if [[ $RESULTS_COUNT -gt 0 ]]; then
  echo "  ✅ Results found ($RESULTS_COUNT files):"
  ssh $AUTOMATION_USER@$WORKER "ls -lht $RESULTS_DIR/*.json 2>/dev/null | head -3 | awk '{print \"     \" \$9 \" (\" \$5 \" bytes)\"}'" 2>/dev/null || true
else
  echo "  ⏳ No results yet (first test scheduled for daily at 2 AM UTC)"
fi

echo ""

# ============================================================================
# SECTION 4: SERVICE LOGS
# ============================================================================
echo "📜 SECTION 4: RECENT SERVICE ACTIVITY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "  Last auto-deploy activity:"
ssh $AUTOMATION_USER@$WORKER "sudo journalctl -u nexusshield-auto-deploy.service -n 3 --no-pager 2>/dev/null | awk '{print \"    \" \$0}'" 2>/dev/null || echo "    (logs not available)"

echo ""
echo "  Last NAS stress test service activity:"
ssh $AUTOMATION_USER@$WORKER "sudo journalctl -u nas-stress-test.service -n 3 --no-pager 2>/dev/null | awk '{print \"    \" \$0}'" 2>/dev/null || echo "    (no test runs yet - scheduled for 2 AM UTC)"

echo ""

# ============================================================================
# SECTION 5: SUMMARY & NEXT STEPS
# ============================================================================
echo "🎯 SECTION 5: DEPLOYMENT SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ $WORKER_COMMIT == *"3d4b61547"* ]] && [[ "$DEPLOY_STATE" == *"DEPLOYED"* ]]; then
  echo "  ✅ STATUS: DEPLOYMENT COMPLETE"
  echo ""
  echo "  Next: Monitor daily test execution (tomorrow 2 AM UTC)"
  echo "  Command: watch -n 60 'bash monitor-nas-deployment.sh'"
elif [[ $AUTODEPLOY_ACTIVITY -gt 0 ]]; then
  echo "  🟡 STATUS: AUTO-DEPLOY IN PROGRESS"
  echo ""
  echo "  Next: Check again in 5 minutes"
  echo "  Command: bash monitor-nas-deployment.sh"
else
  echo "  🟣 STATUS: WAITING FOR AUTO-DEPLOY DETECTION"
  echo ""
  echo "  Timeline: Git push was ~$(($(($(date +%s) - $(date -d '18:35 UTC' +%s 2>/dev/null || echo 0))) / 60)) minutes ago"
  echo "  Expected: Auto-deploy detects within 5-10 minutes of push"
  echo "  Next: Check again in 5 minutes"
  echo "  Command: bash monitor-nas-deployment.sh"
fi

echo ""
echo "📚 Documentation References:"
echo "  • Full Guide: NAS-STRESS-TEST-DEPLOYMENT-GUIDE.md"
echo "  • Status Report: NAS-STRESS-TEST-DEPLOYMENT-STATUS.md"
echo "  • Readiness: NAS-STRESS-TEST-READINESS-CHECKLIST.md"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Generated: $(date)"
echo ""
