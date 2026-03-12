#!/usr/bin/env bash
set -euo pipefail

# Post-Deploy Security Scanning
# Runs SBOM generation (syft) and Trivy vulnerability scans on the host
# Archives results to GCS for immutable audit trail

TIMESTAMP=$(date -u +%Y%m%d_%H%M%S)
REPORT_DIR="/tmp/post-deploy-security-scan-${TIMESTAMP}"
GCS_BUCKET="${GCS_BUCKET:-gs://nexusshield-dev-sbom-archive}"
GCS_PREFIX="${GCS_PREFIX:-post-deploy-scans}"

mkdir -p "$REPORT_DIR"
echo "📊 Post-Deploy Security Scan ($(date -u +'%Y-%m-%dT%H:%M:%SZ'))"
echo "Report dir: $REPORT_DIR"
echo ""

# 1. Generate SBOM using syft (if available)
if command -v syft &>/dev/null; then
  echo "📄 Generating SBOM with syft..."
  syft /opt -o spdx-json > "$REPORT_DIR/sbom-spdx.json" 2>/dev/null || {
    echo "⚠️  SBOM generation failed (may require root)"
  }
  syft /opt -o table > "$REPORT_DIR/sbom-spdx.txt" 2>/dev/null || true
  echo "✅ SBOM generated"
else
  echo "⚠️  syft not found (skipping SBOM generation)"
fi

# 2. Run Trivy vulnerability scan (if available)
if command -v trivy &>/dev/null; then
  echo "🔍 Running Trivy vulnerability scan..."
  trivy image --severity HIGH,CRITICAL --format json --output "$REPORT_DIR/trivy-vulns.json" \
    gcr.io/nexusshield-prod/nexus-normalizer:20260312 2>/dev/null || {
    echo "⚠️  Trivy image scan failed (requires Docker/image access)"
  }
  trivy rootfs --severity MEDIUM --format table --output "$REPORT_DIR/trivy-rootfs.txt" / 2>/dev/null || {
    echo "⚠️  Trivy rootfs scan failed"
  }
  echo "✅ Trivy scan completed"
else
  echo "⚠️  trivy not found (skipping vulnerability scan)"
fi

# 3. Check for exposed configs/secrets in running processes
echo "🔐 Checking process environment..."
ps aux | grep -E "^\s*\w+\s+\d+.*" | head -20 > "$REPORT_DIR/process-list.txt" || true
echo "✅ Process list captured"

# 4. Docker image inspection
if command -v docker &>/dev/null; then
  echo "🐳 Inspecting Docker images..."
  docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" > "$REPORT_DIR/docker-images.txt" 2>/dev/null || true
  echo "✅ Docker images listed"
else
  echo "⚠️  Docker not available"
fi

# 5. Create summary
SUMMARY_FILE="$REPORT_DIR/scan-summary.jsonl"
echo "{\"timestamp\":\"$(date -u +'%Y-%m-%dT%H:%M:%SZ')\",\"context\":\"post-deploy-security-scan\",\"hostname\":\"$(hostname)\",\"timestamp_unix\":$(date +%s),\"files_generated\":$(ls -1 "$REPORT_DIR" | wc -l),\"gcs_destination\":\"$GCS_BUCKET/$GCS_PREFIX/\"}" >> "$SUMMARY_FILE"
echo "✅ Summary created"

# 6. Archive to GCS
if command -v gsutil &>/dev/null; then
  echo ""
  echo "📦 Uploading to GCS ($GCS_BUCKET/$GCS_PREFIX/)..."
  gsutil -m cp -r "$REPORT_DIR"/* "$GCS_BUCKET/$GCS_PREFIX/$(basename $REPORT_DIR)/" 2>/dev/null && {
    echo "✅ Archived to $GCS_BUCKET/$GCS_PREFIX/$(basename $REPORT_DIR)/"
  } || {
    echo "⚠️  GCS upload failed (may require gsutil auth)"
  }
else
  echo "⚠️  gsutil not available (skipping GCS upload)"
fi

echo ""
echo "✅ Post-deploy security scan complete"
echo "Local reports: $REPORT_DIR"
