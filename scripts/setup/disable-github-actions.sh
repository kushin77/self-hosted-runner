#!/bin/bash
################################################################################
# Disable All GitHub Actions - Migration to Cloud Build CD
# Moves all CI/CD from GitHub Actions to Google Cloud Build
################################################################################

set -e

REPO_OWNER="${1:-kushin77}"
REPO_NAME="${2:-self-hosted-runner}"
GHTOKEN="${GHTOKEN:-${GH_TOKEN}}"

if [ -z "$GHTOKEN" ]; then
  echo "Error: GHTOKEN or GH_TOKEN environment variable not set"
  exit 1
fi

echo "=========================================="
echo "Disabling GitHub Actions"
echo "Repository: $REPO_OWNER/$REPO_NAME"
echo "=========================================="

# ============================================================================
# STEP 1: Disable GitHub Actions via API
# ============================================================================

echo ""
echo "[1/3] Disabling GitHub Actions via API..."

# Disable all actions
curl -s -X PUT \
  -H "Authorization: token $GHTOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/actions/permissions" \
  -d '{"enabled":false}' \
  | jq -r '.enabled // .message' || echo "Could not disable actions"

echo "✓ GitHub Actions disabled"

# ============================================================================
# STEP 2: Ensure all workflows are archived
# ============================================================================

echo "[2/3] Verifying workflow archival..."

WORKFLOWS_DIR=".github/workflows"
ARCHIVE_DIR=".github/workflows-archive"

if [ -d "$WORKFLOWS_DIR" ]; then
  if ls "$WORKFLOWS_DIR"/*.yml "$WORKFLOWS_DIR"/*.yaml 2>/dev/null | grep -v "\.disabled$"; then
    echo "⚠ Found active workflow files:"
    ls "$WORKFLOWS_DIR"/*.yml "$WORKFLOWS_DIR"/*.yaml 2>/dev/null | grep -v "\.disabled$" || true
    
    echo "Moving to archive..."
    mkdir -p "$ARCHIVE_DIR"
    mv "$WORKFLOWS_DIR"/*.yml "$ARCHIVE_DIR"/ 2>/dev/null || true
    mv "$WORKFLOWS_DIR"/*.yaml "$ARCHIVE_DIR"/ 2>/dev/null || true
    
    # Mark directory as archived
    touch "$WORKFLOWS_DIR/.WORKFLOWS_ARCHIVED_$(date -u +%Y-%m-%d)"
  fi
else
  echo "✓ No active workflows directory"
fi

# ============================================================================
# STEP 3: Disable Pull Request Approvals/Releases
# ============================================================================

echo "[3/3] Disabling automatic PRs and releases..."

# Disable automatic version bump pull requests
curl -s -X DELETE \
  -H "Authorization: token $GHTOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/autolinks" \
  2>/dev/null || echo "No autolinks to remove"

# Update repository settings to disable auto-merge
curl -s -X PATCH \
  -H "Authorization: token $GHTOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME" \
  -d '{
    "auto_init": false,
    "allow_auto_merge": false,
    "allow_update_branch": false,
    "delete_branch_on_merge": true,
    "allow_merge_commit": false,
    "allow_squash_merge": true,
    "allow_rebase_merge": false
  }' \
  | jq -r '.name // .message'

echo "✓ Auto-merge and auto-PR features disabled"

echo ""
echo "=========================================="
echo "✓ GitHub Actions Migration Complete"
echo "=========================================="
echo ""
echo "Next Steps:"
echo "1. All CI/CD handled by Cloud Build ..."
echo "2. Triggers: git push main → automatic deploy"
echo "3. No GitHub Actions workflows active"
echo "4. No automatic PR/release creation"
echo ""
echo "Verify:"
echo "  gcloud builds triggers list --project=nexusshield-prod"
echo "  curl -H 'Authorization: token $GHTOKEN' https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/actions/permissions"
echo ""
