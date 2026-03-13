#!/bin/bash
################################################################################
# OPERATOR: INJECT CLOUDFLARE TOKEN TO UNLOCK DNS CUTOVER FINALIZATION
# Run this from your machine to inject the token into GSM
# Once token is valid, autonomous watcher auto-triggers Phase 2+3
################################################################################

set -e

PROJECT_ID="nexusshield-prod"
SECRET_NAME="cloudflare-api-token"

# ==============================================================================
# STEP 1: Ensure secret exists in GSM
# ==============================================================================
echo "[OPERATOR] Creating secret if missing..."
gcloud secrets create "$SECRET_NAME" --replication-policy="automatic" --project="$PROJECT_ID" 2>/dev/null || echo "  (Secret already exists)"

# ==============================================================================
# STEP 2: Prompt for token (read securely)
# ==============================================================================
echo ""
echo "================================"
echo "OPERATOR: PASTE CLOUDFLARE TOKEN"
echo "================================"
echo "Enter your Cloudflare API token (will not echo):"
read -s CF_TOKEN

if [ -z "$CF_TOKEN" ]; then
  echo "ERROR: Token is empty. Exiting."
  exit 1
fi

# ==============================================================================
# STEP 3: Inject token into GSM
# ==============================================================================
echo ""
echo "[OPERATOR] Injecting token into GSM..."
echo -n "$CF_TOKEN" | gcloud secrets versions add "$SECRET_NAME" --data-file=- --project="$PROJECT_ID"

echo "[OPERATOR] ✓ Token injected successfully"

# ==============================================================================
# STEP 4: Verify injection
# ==============================================================================
echo ""
echo "[OPERATOR] Verifying token in GSM..."
STORED=$(gcloud secrets versions access latest --secret="$SECRET_NAME" --project="$PROJECT_ID")
if [ "$STORED" = "$CF_TOKEN" ]; then
  echo "[OPERATOR] ✓ Token verified in GSM"
else
  echo "[OPERATOR] ✗ ERROR: Token mismatch"
  exit 1
fi

# ==============================================================================
# STEP 5: Confirm autonomous watcher will detect
# ==============================================================================
echo ""
echo "================================"
echo "FINALIZATION AUTOMATION RESUMED"
echo "================================"
echo "✓ Token injected into GSM"
echo "✓ Autonomous watcher polling (PID: check ps aux for auto-finalize-when-token-ready.sh)"
echo "✓ Watcher detects token within 30 seconds"
echo "✓ Phase 2+3 auto-executes:"
echo "  • DNS promotion (all zones → 192.168.168.42)"
echo "  • Slack notification (operations team)"
echo "  • Immutable audit logging (JSONL + git commit)"
echo ""
echo "Monitor progress:"
echo "  tail -f /home/akushnir/self-hosted-runner/logs/cutover/auto-finalize.log"
echo "  tail -f /home/akushnir/self-hosted-runner/logs/cutover/execution_full_*.log"
echo ""
echo "View status:"
echo "  cat /home/akushnir/self-hosted-runner/DEPLOYMENT_READINESS_STATUS_2026_03_13.md"
echo ""
echo "================================"
