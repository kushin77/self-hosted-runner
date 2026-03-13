#!/bin/bash
################################################################################
# DEPLOYMENT EXECUTION COMMAND - Copy/Paste Ready
# Last Updated: 2026-03-13T13:10:00Z
#
# QUICK START: Copy token value and paste command below directly in terminal
################################################################################

# ============================================================================
# STEP 1: OBTAIN CLOUDFLARE API TOKEN (5 minutes)
# ============================================================================
# 
# 1. Go to: https://dash.cloudflare.com/
# 2. Click User Icon (bottom left) → My Profile → API Tokens
# 3. Create Token with these permissions:
#    - Zone | DNS | Edit
#    - Zone Resources | All | All
# 4. Confirm and Copy Token
#
# Token format: v1.0<alphanumeric_string>
#
# ============================================================================
# STEP 2: INJECT TOKEN & AUTO-EXECUTE PHASE 2+3 (1 minute)
# ============================================================================
#
# PASTE THIS COMMAND (replace <TOKEN_VALUE> with actual token):
#
# cd /home/akushnir/self-hosted-runner && bash scripts/ops/operator-inject-token.sh "<TOKEN_VALUE>"
#
# Expected output:
#   [2026-03-13T13:XX:XXZ] TOKEN INJECTION: Starting
#   ✓ Token added to GSM
#   ✓ Token verified in GSM
#   ✅ TOKEN READY — Triggering Phase 2+3 finalization...
#   [2026-03-13T13:XX:XXZ] PHASE 2: FULL DNS PROMOTION - STARTING
#   ✓ CF_API_TOKEN loaded from GSM secret: cloudflare-api-token
#   [... Phase 2 details ...]
#   ✓ PHASE 2: Full DNS promotion completed successfully
#   [2026-03-13T13:XX:XXZ] PHASE 3: STAKEHOLDER NOTIFICATIONS - STARTING
#   ✓ Slack notification sent to operations team
#   ✓ DEPLOYMENT FINALIZED (immutable, idempotent, hands-off)
#
# ============================================================================
# STEP 3: MONITOR PHASE 4 (24 hours)
# ============================================================================
#
# After Phase 2+3 complete, Phase 4 validation begins automatically.
# Poller is already running (PID: see logs/cutover/poller.log)
#
# Monitor dashboard:
#   → http://192.168.168.42:3000 (Grafana)
#   → http://192.168.168.42:9090 (Prometheus)
#
# Watch for:
#   ✅ Error rate < 0.1% (from Prometheus)
#   ✅ All 13 services healthy (from Prometheus up metric)
#   ✅ No DNS failures
#   ✅ Latencies within normal range
#
# Duration: 24 hours minimum (automated poller monitors continuously)
#
# ============================================================================
# STEP 4: CLOSE ISSUES (after 24h validation)
# ============================================================================
#
# Once Phase 4 validation complete:
#   1. Review logs/cutover/poller.log (should show "healthy" status)
#   2. Review Grafana dashboard (24h trend should be flat/green)
#   3. Close Issue #1 and #2 in issues/DEPLOYMENT_ISSUES.md
#   4. Deployment complete! ✅
#
# ============================================================================

echo "DEPLOYMENT EXECUTION COMMAND"
echo ""
echo "Paste this command to inject token and auto-execute Phase 2+3:"
echo ""
echo 'cd /home/akushnir/self-hosted-runner && bash scripts/ops/operator-inject-token.sh "<CF_API_TOKEN>"'
echo ""
echo "Replace <CF_API_TOKEN> with your actual Cloudflare API token (e.g., v1.0abc123xyz)"
echo ""
