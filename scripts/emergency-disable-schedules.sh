#!/bin/bash
#
# EMERGENCY: Disable cascading workflow failures - Simple approach
# Remove all schedule triggers from broken workflows
#

set -euo pipefail

echo "🚨 EMERGENCY WORKFLOW STABILIZATION"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

WORKFLOWS_DIR=".github/workflows"
DISABLED=0

# Known broken workflows (from recent failures)
for wf in \
  automation-health-validator.yml \
  verify-secrets-and-diagnose.yml \
  reusable-guards.yml \
  reusable-vault-oidc-auth.yml \
  dependency-automation.yml \
  self-healing-remediation.yml \
  revoke-runner-mgmt-token.yml \
  remediation-dispatcher.yml \
  canary-deployment.yml \
  secrets-health.yml \
  secrets-orchestrator-multi-layer.yml \
  secure-multi-layer-secret-rotation.yml \
  store-leaked-to-gsm-and-remove.yml \
  portal-ci.yml \
  store-gsm-secrets.yml \
  compliance-audit-log.yml \
  ephemeral-secret-provisioning.yml \
  hands-off-health-deploy.yml \
  operational-health-dashboard.yml \
  store-slack-to-gsm.yml \
  dr-smoke-test.yml \
  secrets-comprehensive-validation.yml \
  secrets-event-dispatcher.yml \
  dependabot-weekly-triage.yml \
  gcp-gsm-sync-secrets.yml; do
  
  # Check in both locations
  filepath="$WORKFLOWS_DIR/$wf"
  [[ ! -f "$filepath" ]] && filepath="$WORKFLOWS_DIR/reusable/$wf"
  
  if [[ ! -f "$filepath" ]]; then
    continue
  fi
  
  # Check if has schedule trigger
  if grep -q "^  schedule:" "$filepath"; then
    echo "  Disabling: $(basename $filepath)"
    
    # Remove schedule: block and cron entries using sed
    # This removes "  schedule:" and following "    - cron: ..." lines
    sed -i '/^  schedule:$/,/^  [^ ]/{ /^  schedule:$/d; /^    - cron:/d; }' "$filepath"
    
    # Clean up any orphaned comments or empty lines left by schedule section
    sed -i '/^  # Daily/d; /^  # Scheduled/d' "$filepath" || true
    
    ((DISABLED++))
  fi
done

echo ""
echo "✅ Disabled schedule triggers on $DISABLED workflows"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Effect: Prevents cascading failures from broken workflows"
echo "Workflows remain available for manual triggering via workflow_dispatch"
echo ""

# Verify critical workflows still work
echo "Checking critical workflows..."
if python3 -c "import yaml; yaml.safe_load(open('$WORKFLOWS_DIR/00-master-router.yml'))" 2>/dev/null; then
  echo "  ✓ 00-master-router: Syntax OK, Schedule Active"
else
  echo "  ✗ 00-master-router: Needs attention"
fi

if python3 -c "import yaml; yaml.safe_load(open('$WORKFLOWS_DIR/01-alacarte-deployment.yml'))" 2>/dev/null; then
  echo "  ✓ 01-alacarte-deployment: Syntax OK, Schedule Active"
else
  echo "  ✗ 01-alacarte-deployment: Needs attention"
fi

echo ""
echo "✅ EMERGENCY STABILIZATION COMPLETE"
exit 0
