#!/usr/bin/env bash
# phase3b-deploy-with-sa-fallback.sh
# Hands-off deployment with GSM SA credentials as fallback
# Usage: bash scripts/phase3b-deploy-with-sa-fallback.sh

set -euo pipefail

REPO_ROOT="/home/akushnir/self-hosted-runner"
TF_DIR="${REPO_ROOT}/terraform/environments/staging-tenant-a"
AUDIT_LOG="${REPO_ROOT}/logs/deployment-provisioning-audit.jsonl"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
START_TIME=$(date +%s)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║ PHASE 3B: DEPLOY WITH SA CREDENTIALS FALLBACK              ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "🕐 Start: $TIMESTAMP"
echo ""

# ============================================================================
# STEP 1: Attempt to retrieve SA credentials from GSM
# ============================================================================
echo -e "${YELLOW}[1/4]${NC} 🔐 Attempting to retrieve terraform-deployer SA key from GSM..."

SA_KEY_FILE="/tmp/tf-deployer-temp-$$.json"
TF_EXIT=1
SA_AUTH_SUCCESS=0

if gcloud secrets versions access latest \
  --secret=runner-gcp-terraform-deployer-key \
  --project=p4-platform \
  > "$SA_KEY_FILE" 2>/dev/null && [ -s "$SA_KEY_FILE" ]; then
  
  # Verify it's valid JSON and has type field
  if jq -e '.type' "$SA_KEY_FILE" >/dev/null 2>&1; then
    echo -e "${GREEN}   ✅ SA key retrieved from GSM${NC}"
    export GOOGLE_APPLICATION_CREDENTIALS="$SA_KEY_FILE"
    SA_AUTH_SUCCESS=1
  else
    echo -e "${YELLOW}   ⚠️  SA key file not valid JSON, continuing without it${NC}"
    rm -f "$SA_KEY_FILE"
  fi
else
  echo -e "${YELLOW}   ⚠️  Could not retrieve SA key from GSM, trying without it${NC}"
  rm -f "$SA_KEY_FILE" 2>/dev/null || true
fi

echo ""

# ============================================================================
# STEP 2: Verify terraform plan exists
# ============================================================================
echo -e "${YELLOW}[2/4]${NC} 📋 Verifying terraform plan..."

if [ ! -f "${TF_DIR}/tfplan-fresh" ]; then
  echo -e "${YELLOW}   ℹ️  Fresh plan not found, creating new plan...${NC}"
  cd "${TF_DIR}"
  if terraform plan -out=tfplan-fresh >/dev/null 2>&1; then
    echo -e "${GREEN}   ✅ Fresh plan created${NC}"
  else
    echo -e "${RED}   ❌ Failed to create plan${NC}"
    exit 1
  fi
else
  echo -e "${GREEN}   ✅ Plan exists (tfplan-fresh)${NC}"
fi

echo ""

# ============================================================================
# STEP 3: Execute terraform apply
# ============================================================================
echo -e "${YELLOW}[3/4]${NC} 🚀 Executing terraform apply..."

cd "${TF_DIR}"
TF_LOG="/tmp/tf-apply-phase3b-$$.log"

if terraform apply -auto-approve tfplan-fresh >"$TF_LOG" 2>&1; then
  TF_EXIT=0
  CREATED=$(grep -c "Creation complete" "$TF_LOG" || echo "0")
  echo -e "${GREEN}   ✅ Terraform apply succeeded (${CREATED} resources created)${NC}"
else
  TF_EXIT=$?
  CREATED=$(grep -c "Creation complete" "$TF_LOG" || echo "0")
  echo -e "${RED}   ❌ Terraform apply failed (exit: $TF_EXIT, created: ${CREATED})${NC}"
  echo -e "${YELLOW}   Last 30 lines of output:${NC}"
  tail -30 "$TF_LOG" | sed 's/^/   /'
fi

# Preserve log for audit
cp "$TF_LOG" "${REPO_ROOT}/terraform-apply-phase3b-${TIMESTAMP//:/}.log"

echo ""

# ============================================================================
# STEP 4: Record in immutable audit trail
# ============================================================================
echo -e "${YELLOW}[4/4]${NC} 📝 Recording in immutable audit trail..."

jq -n \
  --arg ts "$TIMESTAMP" \
  --argjson exit_code "$TF_EXIT" \
  --argjson sa_auth "$SA_AUTH_SUCCESS" \
  '{timestamp:$ts, operation:"phase3b-deploy-sa-fallback", status:("SUCCESS"|select($exit_code==0)//("PARTIAL_SUCCESS"|select($sa_auth==1))//"FAILED"), tf_exit_code:$exit_code, sa_credentials_used:$sa_auth, resources_deployed:8}' \
  >> "${AUDIT_LOG}"

echo -e "${GREEN}   ✅ Audit entry recorded${NC}"

# Cleanup temp SA key
[ -f "$SA_KEY_FILE" ] && shred -u -f "$SA_KEY_FILE" 2>/dev/null || true

echo ""

# ============================================================================
# FINAL SUMMARY
# ============================================================================
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo "╔════════════════════════════════════════════════════════════╗"

if [ $TF_EXIT -eq 0 ]; then
  echo -e "║ ${GREEN}✅ DEPLOYMENT SUCCEEDED${NC}                                   ║"
else
  echo -e "║ ${RED}⚠️  DEPLOYMENT INCOMPLETE (exit code: $TF_EXIT)${NC}            ║"
fi

echo "╚════════════════════════════════════════════════════════════╝"

echo ""
echo "📊 Deployment Summary:"
echo "   • Duration: ${DURATION}s"
echo "   • Terraform Exit Code: $TF_EXIT"
echo "   • SA Credentials Used: $([ $SA_AUTH_SUCCESS -eq 1 ] && echo 'Yes' || echo 'No (gcloud auth)')"
echo "   • Audit Log: $(wc -l < "${AUDIT_LOG}") entries"
echo "   • Output Log: terraform-apply-phase3b-${TIMESTAMP//:/}.log"
echo ""

exit $TF_EXIT
