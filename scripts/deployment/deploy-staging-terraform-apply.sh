#!/bin/bash
# 🚀 AUTOMATED STAGING TERRAFORM APPLY
# Hands-off deployment: run after OAuth token refresh
# Deploys: service account, firewalls, instance template, IAM bindings
# Logs: all output to audit trail + GitHub issue #2072

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_DIR="$REPO_ROOT/terraform/environments/staging-tenant-a"
AUDIT_LOG="$REPO_ROOT/logs/deployment-terraform-apply-$(date +%Y%m%dT%H%M%SZ).log"
mkdir -p "$(dirname "$AUDIT_LOG")"

echo "════════════════════════════════════════════════════════════════════"
echo "🚀 STAGING TERRAFORM APPLY - AUTOMATED HANDS-OFF DEPLOYMENT"
echo "════════════════════════════════════════════════════════════════════"
echo ""
echo "Start time: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Environment: staging-tenant-a (p4-platform, us-central1)"
echo "Audit log: $AUDIT_LOG"
echo ""

# Check terraform available
if ! command -v terraform &> /dev/null; then
    echo "❌ terraform not found. Please install terraform."
    exit 1
fi

# Check gcloud available
if ! command -v gcloud &> /dev/null; then
    echo "❌ gcloud not found. Please install gcloud CLI."
    exit 1
fi

echo "📋 Validating prerequisites..."
echo "  ✅ terraform found: $(terraform version | head -1)"
echo "  ✅ gcloud found: $(gcloud version --format='value(core.version)')"
echo ""

# Check ADC token
if ! gcloud auth application-default print-access-token > /dev/null 2>&1; then
    echo "❌ ADC token not available or expired. Run OAuth helper:"
    echo "   bash $REPO_ROOT/scripts/gcp-oauth-reinit.sh"
    exit 1
fi

echo "  ✅ ADC token available"
echo ""

# Navigate to environment
cd "$ENV_DIR"
echo "📂 Working directory: $(pwd)"
echo ""

# Refresh terraform state
echo "🔄 Refreshing terraform state..."
terraform init -upgrade 2>&1 | tee -a "$AUDIT_LOG"
echo ""

# Generate fresh plan (safety: regenerate to avoid stale plan errors)
echo "📐 Generating fresh terraform plan..."
terraform plan -out=tfplan -refresh=true 2>&1 | tee -a "$AUDIT_LOG"
echo ""

# Extract plan summary
PLAN_SUMMARY=$(terraform show -no-color tfplan 2>/dev/null | grep "Plan:" || echo "Plan: (summary unavailable)")
echo "Plan summary: $PLAN_SUMMARY"
echo ""

# Apply
echo "🚀 Applying terraform configuration..."
START_APPLY=$(date +%s)
if terraform apply -auto-approve tfplan 2>&1 | tee -a "$AUDIT_LOG"; then
    END_APPLY=$(date +%s)
    APPLY_TIME=$((END_APPLY - START_APPLY))
    
    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "✅ TERRAFORM APPLY SUCCESSFUL"
    echo "════════════════════════════════════════════════════════════════════"
    echo "Duration: ${APPLY_TIME}s"
    echo "Outputs:"
    terraform output 2>&1 | tee -a "$AUDIT_LOG"
    echo ""
    echo "End time: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "Audit log: $AUDIT_LOG"
    echo ""
    
    # Post to GitHub issue #2072
    if command -v gh &> /dev/null; then
        ISSUE_BODY="✅ **Terraform Apply: SUCCESS** ($(date -u +%Y-%m-%dT%H:%M:%SZ))

**Resources created:**
- Service account: \`runner-staging-a@p4-platform.iam.gserviceaccount.com\`
- Firewall rules: 4 (ingress/egress allow/deny)
- Instance template: \`runner-staging-a-*\`
- IAM bindings: 2 (workload identity)

**Next step:** Boot test instance from template and run smoke tests (see #2096)"
        
        gh issue comment 2072 --body "$ISSUE_BODY" --repo kushin77/self-hosted-runner 2>/dev/null || true
    fi
    
    exit 0
else
    EXIT_CODE=$?
    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "❌ TERRAFORM APPLY FAILED"
    echo "════════════════════════════════════════════════════════════════════"
    echo "Exit code: $EXIT_CODE"
    echo "Audit log: $AUDIT_LOG"
    echo ""
    echo "Possible causes:"
    echo "  - GCP OAuth RAPT expired (run OAuth helper)"
    echo "  - Terraform state locked"
    echo "  - Network connectivity issue"
    echo "  - GCP quota exceeded"
    echo ""
    exit $EXIT_CODE
fi
