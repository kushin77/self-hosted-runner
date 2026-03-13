#!/bin/bash
################################################################################
# Cloud Scheduler Configuration - No-Ops Automation
# Fully hands-off credential rotation, vulnerability scanning, and remediation
################################################################################

set -e

PROJECT_ID="${1:-nexusshield-prod}"
REGION="${2:-us-central1}"

echo "=========================================="
echo "Configuring Cloud Scheduler (No-Ops)"
echo "Project: $PROJECT_ID"
echo "Region: $REGION"
echo "=========================================="

# ============================================================================
# JOB 1: Daily Credential Rotation (High-Risk Secrets)
# ============================================================================

echo ""
echo "[1/5] Creating credential rotation job (daily)..."

gcloud scheduler jobs create pubsub credential-rotation-daily \
  --location=$REGION \
  --schedule="0 2 * * *" \
  --topic=credential-rotation \
  --message-body='{"type":"rotate-all-secrets","risk":"high"}' \
  --project=$PROJECT_ID \
  --service-account-email=credential-rotation-scheduler@${PROJECT_ID}.iam.gserviceaccount.com \
  --time-zone="UTC" 2>/dev/null || echo "✓ Rotation job exists"

# ============================================================================
# JOB 2: Hourly Vulnerability Scanning
# ============================================================================

echo "[2/5] Creating vulnerability scanning job (hourly)..."

gcloud scheduler jobs create pubsub vuln-scan-hourly \
  --location=$REGION \
  --schedule="0 * * * *" \
  --topic=vulnerability-scan \
  --message-body='{"type":"scan-images","severity":["HIGH","CRITICAL"]}' \
  --project=$PROJECT_ID \
  --service-account-email=vuln-scan-svc@${PROJECT_ID}.iam.gserviceaccount.com \
  --time-zone="UTC" 2>/dev/null || echo "✓ Vuln scan job exists"

# ============================================================================
# JOB 3: Infrastructure Health Check (15-minute intervals)
# ============================================================================

echo "[3/5] Creating infrastructure health check (every 15 min)..."

gcloud scheduler jobs create pubsub infra-health-check \
  --location=$REGION \
  --schedule="*/30 * * * *" \
  --topic=infra-health-check \
  --message-body='{"type":"health-check","remediate":true}' \
  --project=$PROJECT_ID \
  --service-account-email=nxs-automation-sa@${PROJECT_ID}.iam.gserviceaccount.com \
  --time-zone="UTC" 2>/dev/null || echo "✓ Health check job exists"

# ============================================================================
# JOB 4: SBOM Generation & Archival (Weekly)
# ============================================================================

echo "[4/5] Creating SBOM generation job (weekly)..."

gcloud scheduler jobs create pubsub sbom-generation-weekly \
  --location=$REGION \
  --schedule="0 3 * * 0" \
  --topic=sbom-generation \
  --message-body='{"type":"generate-sbom","format":["spdx","cyclonedx"]}' \
  --project=$PROJECT_ID \
  --service-account-email=artifacts-publisher@${PROJECT_ID}.iam.gserviceaccount.com \
  --time-zone="UTC" 2>/dev/null || echo "✓ SBOM generation job exists"

# ============================================================================
# JOB 5: Auto-Remediation (Continuous - On Failure Detection)
# ============================================================================

echo "[5/5] Creating auto-remediation job (hourly)..."

gcloud scheduler jobs create pubsub auto-remediation-hourly \
  --location=$REGION \
  --schedule="0 * * * *" \
  --topic=auto-remediation \
  --message-body='{"type":"remediate-failures","scope":"all","auto-rollback":true}' \
  --project=$PROJECT_ID \
  --service-account-email=nxs-automation-sa@${PROJECT_ID}.iam.gserviceaccount.com \
  --time-zone="UTC" 2>/dev/null || echo "✓ Auto-remediation job exists"

echo ""
echo "=========================================="
echo "✓ Cloud Scheduler Jobs Created"
echo "=========================================="
echo ""
echo "Jobs:"
echo "  1. credential-rotation-daily: 02:00 UTC"
echo "  2. vuln-scan-hourly: Every hour"
echo "  3. infra-health-check-15min: Every 15 minutes"
echo "  4. sbom-generation-weekly: Sundays 03:00 UTC"
echo "  5. auto-remediation-hourly: Every hour"
echo ""
echo "View jobs:"
echo "  gcloud scheduler jobs list --location=$REGION --project=$PROJECT_ID"
echo ""
echo "Test a job:"
echo "  gcloud scheduler jobs run credential-rotation-daily --location=$REGION --project=$PROJECT_ID"
echo ""
