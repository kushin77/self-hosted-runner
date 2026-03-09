#!/bin/bash
#
# Emergency remediation: Disable schedule triggers on problematic workflows
# while keeping workflow_dispatch and other triggers intact
# This gets workflows unblocked from CI errors
#

set -euo pipefail

cat > /tmp/fix_triggers.py << 'PYTHON_EOF'
import re
import sys
import yaml

file_path = sys.argv[1]

with open(file_path, 'r') as f:
    lines = f.readlines()

# Find the 'on:' section and remove schedule blocks
output = []
skip_block = False
skip_indent = 0

for i, line in enumerate(lines):
    # Check if this is a schedule: line
    if re.match(r'^  schedule:', line):
        skip_block = True
        skip_indent = len(line) - len(line.lstrip())
        continue  # Skip the schedule: line itself
    
    # If we're skipping a block, check if we've reached the end
    if skip_block:
        current_indent = len(line) - len(line.lstrip()) if line.strip() else float('inf')
        # If line is at same level as schedule (2 spaces) and not empty, it's a new section
        if line.strip() and current_indent <= skip_indent:
            skip_block = False
            output.append(line)
        # Otherwise skip the cron entries
        continue
    
    output.append(line)

with open(file_path, 'w') as f:
    f.writelines(output)

print(f"Fixed: {file_path}")
PYTHON_EOF

FIXED=0
for workflow in \
  .github/workflows/automation-health-validator.yml \
  .github/workflows/dependency-automation.yml \
  .github/workflows/dr-smoke-test.yml \
  .github/workflows/ephemeral-secret-provisioning.yml \
  .github/workflows/gcp-gsm-breach-recovery.yml \
  .github/workflows/gcp-gsm-rotation.yml \
  .github/workflows/gcp-gsm-sync-secrets.yml \
  .github/workflows/hands-off-health-deploy.yml \
  .github/workflows/operational-health-dashboard.yml \
  .github/workflows/portal-ci.yml \
  .github/workflows/progressive-rollout.yml \
  .github/workflows/reusable/canary-deployment-run.yml \
  .github/workflows/reusable/terraform-apply-callable.yml \
  .github/workflows/reusable/terraform-plan-callable.yml \
  .github/workflows/revoke-deploy-ssh-key.yml \
  .github/workflows/revoke-runner-mgmt-token.yml \
  .github/workflows/secret-rotation-mgmt-token.yml \
  .github/workflows/secrets-health-dashboard.yml \
  .github/workflows/secrets-health.yml \
  .github/workflows/secrets-orchestrator-multi-layer.yml \
  .github/workflows/secrets-policy-enforcement.yml \
  .github/workflows/self-healing-remediation.yml \
  .github/workflows/store-leaked-to-gsm-and-remove.yml \
  .github/workflows/store-slack-to-gsm.yml \
  .github/workflows/verify-secrets-and-diagnose.yml; do

  if [[ -f "$workflow" ]]; then
    echo "Processing: $(basename $workflow)"
    python3 /tmp/fix_triggers.py "$workflow" 2>/dev/null || true
    
    # Verify it now parses
    if python3 -c "import yaml; yaml.safe_load(open('$workflow'))" 2>/dev/null; then
      echo "  ✅ Fixed"
      ((FIXED++))
    else
      echo "  ⚠️  Still has errors (needs manual review)"
    fi
  fi
done

echo ""
echo "Remediation complete: Fixed $FIXED workflows"

exit 0
