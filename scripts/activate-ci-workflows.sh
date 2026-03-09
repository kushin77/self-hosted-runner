#!/usr/bin/env bash
# Helper script to document workflow activation needs

REPO="kushin77/self-hosted-runner"
OWNER="kushin77"

echo "=== CI/CD WORKFLOW ACTIVATION GUIDE ==="
echo ""
echo "To activate workflows in GitHub Actions UI:"
echo "1. Go to: https://github.com/$OWNER/$REPO/actions"
echo "2. In left sidebar, find each workflow:"
echo "   - revoke-runner-mgmt-token"
echo "   - secrets-policy-enforcement"
echo "   - deploy"
echo "3. Click workflow name → Click 'Enable workflow' button"
echo "4. Verify status changes to 'Active' (green checkmark)"
echo ""
echo "After activation:"
echo "- Health checks run automatically every hour"
echo "- CI/CD automation becomes fully operational"
echo "- Monitor: https://github.com/$OWNER/$REPO/actions"
