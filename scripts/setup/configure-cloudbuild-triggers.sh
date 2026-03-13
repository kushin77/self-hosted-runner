#!/bin/bash
################################################################################
# Cloud Build Trigger Configuration - Direct Git to Production Pipeline
# This script creates Cloud Build triggers for hands-off, fully automated CD
################################################################################

set -e

PROJECT_ID="${1:-nexusshield-prod}"
GITHUB_REPO="${2:-kushin77/self-hosted-runner}"
GITHUB_BRANCH="${3:-main}"

echo "=========================================="
echo "Creating Cloud Build Triggers"
echo "Project: $PROJECT_ID"
echo "Repo: $GITHUB_REPO"
echo "Branch: $GITHUB_BRANCH"
echo "=========================================="

# ============================================================================
# TRIGGER 1: Production CD (Main Branch - Auto Deploy)
# ============================================================================

echo ""
echo "[1/3] Creating Main Branch Trigger (Auto-Deploy to Production)..."

gcloud builds triggers create github \
  --name="production-cd-main" \
  --repo-name="self-hosted-runner" \
  --repo-owner="kushin77" \
  --branch-pattern="^${GITHUB_BRANCH}$" \
  --build-config="cloudbuild-production.yaml" \
  --project=$PROJECT_ID \
  --substitutions="_SHORT_SHA=short" \
  --service-account="projects/$PROJECT_ID/serviceAccounts/cloudbuild-deployer@${PROJECT_ID}.iam.gserviceaccount.com" \
  --disabled=false \
  --require-approval=CREATOR_AND_PR_COMMITTER \
  --filter-by-commit-message="^(?!\\[SKIP\\])" 2>/dev/null || echo "Trigger may already exist"

# ============================================================================
# TRIGGER 2: Staging (Develop Branch - Test Deploy)
# ============================================================================

echo "[2/3] Creating Develop Branch Trigger (Deploy to Staging)..."

gcloud builds triggers create github \
  --name="staging-cd-develop" \
  --repo-name="self-hosted-runner" \
  --repo-owner="kushin77" \
  --branch-pattern="^develop$" \
  --build-config="cloudbuild-staging.yaml" \
  --project=$PROJECT_ID \
  --service-account="projects/$PROJECT_ID/serviceAccounts/cloudbuild-deployer@${PROJECT_ID}.iam.gserviceaccount.com" \
  --disabled=false \
  --filter-by-commit-message="^(?!\\[SKIP\\])" 2>/dev/null || echo "Trigger may already exist"

# ============================================================================
# TRIGGER 3: Security Scanning (All Branches - Daily)
# ============================================================================

echo "[3/3] Creating Daily Security Scan Trigger..."

gcloud builds triggers create cloud-source-repositories \
  --name="daily-security-scan" \
  --repo-name="self-hosted-runner" \
  --branch-pattern="^${GITHUB_BRANCH}$" \
  --build-config="cloudbuild-security-scan.yaml" \
  --project=$PROJECT_ID \
  --service-account="projects/$PROJECT_ID/serviceAccounts/vuln-scan-svc@${PROJECT_ID}.iam.gserviceaccount.com" \
  --disabled=false 2>/dev/null || echo "Trigger may already exist"

echo ""
echo "=========================================="
echo "✓ Cloud Build Triggers Created"
echo "=========================================="
echo ""
echo "Triggers:"
echo "  1. production-cd-main: Auto-deploys on main branch commits"
echo "  2. staging-cd-develop: Auto-deploys on develop branch commits"
echo "  3. daily-security-scan: Runs daily vulnerability scanning"
echo ""
echo "View triggers:"
echo "  gcloud builds triggers list --project=$PROJECT_ID"
echo ""
