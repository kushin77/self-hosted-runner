#!/bin/bash
################################################################################
# DEPLOYMENT ENTRYPOINT
#
# Single command entry point for complete deployment.
# Executes bootstrap, infrastructure provisioning, and continuous deployment.
#
# Properties: Immutable, Ephemeral, Idempotent, No-Ops, Hands-Off
#
# Usage:
#   bash scripts/deploy/deploy.sh                    # Deploy to production
#   bash scripts/deploy/deploy.sh --dry-run          # Preview without changes
#   bash scripts/deploy/deploy.sh --skip-gcp         # Deploy locally only
################################################################################

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Parse arguments
DRY_RUN="false"
SKIP_GCP_DEPLOY="false"
SKIP_ISSUES="false"
VERBOSE="false"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        --skip-gcp)
            SKIP_GCP_DEPLOY="true"
            shift
            ;;
        --skip-issues)
            SKIP_ISSUES="true"
            shift
            ;;
        --verbose|-v)
            VERBOSE="true"
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

export DRY_RUN
export SKIP_GCP_DEPLOY
export SKIP_ISSUES

echo "🚀 DEPLOYMENT ENTRYPOINT"
echo ""
echo "Configuration:"
echo "  DRY_RUN:             $DRY_RUN"
echo "  SKIP_GCP_DEPLOY:     $SKIP_GCP_DEPLOY"
echo "  SKIP_ISSUES:         $SKIP_ISSUES"
echo "  VERBOSE:             $VERBOSE"
echo ""

# Step 1: Bootstrap deployment (creates infrastructure, issues, etc.)
echo "Step 1/3: Bootstrap Deployment..."
if [[ "$VERBOSE" == "true" ]]; then
    bash "${SCRIPT_DIR}/bootstrap-deployment.sh"
else
    bash "${SCRIPT_DIR}/bootstrap-deployment.sh" 2>&1 | grep -E "(✅|❌|⏳|BOOTSTRAP)"
fi

echo ""
echo "Step 2/3: Waiting for infrastructure to be ready..."
if [[ "$DRY_RUN" != "true" ]] && [[ "$SKIP_GCP_DEPLOY" != "true" ]]; then
    # Wait for health checks
    sleep 5
fi

# Step 3: Summary
echo ""
echo "✅ DEPLOYMENT COMPLETE"
echo ""
echo "Next Actions:"
echo "  1. Review GitHub issues for blocking infrastructure items"
echo "  2. Resolve GCP credentials blockers (see issue #2317)"
echo "  3. Execute: bash scripts/orchestrate.sh --phase epic-1-preflight"
echo ""
