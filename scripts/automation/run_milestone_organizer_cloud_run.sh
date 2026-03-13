#!/bin/bash
# Startup script for Cloud Run: metrics server + periodic organizer execution
set -euo pipefail

echo "🚀 Milestone Organizer Cloud Run Startup ($(date -u +'%Y-%m-%dT%H:%M:%SZ'))"

# Ensure we're in the app directory and git repo is initialized
cd /app
if [[ ! -d .git ]]; then
  echo "Initializing git repository..."
  git init . >/dev/null 2>&1 || true
  git config user.email "organizer@nexusshield.com" 2>/dev/null || true
  git config user.name "Milestone Organizer" 2>/dev/null || true
  # Add remote for pushes (even if we don't use it, gh needs it)
  git remote add origin https://github.com/kushin77/self-hosted-runner.git >/dev/null 2>&1 || true
fi

# Start metrics server in background (listens on 8080)
echo "📊 Starting metrics server on port 8080..."
python3 /app/scripts/monitoring/metrics_server.py &
METRICS_PID=$!
echo "📊 Metrics server PID: $METRICS_PID"

# Export credential helpers for organizer
export GH_TOKEN="${GH_TOKEN:-$(gcloud secrets versions access latest --secret=github-token 2>/dev/null || true)}"
export AWS_REGION="${AWS_REGION:-us-west-2}"

# Run organizer once on startup
echo "🎯 Running milestone organizer on startup..."
cd /app && /bin/bash /app/scripts/automation/run_milestone_organizer_v2.sh || {
  echo "⚠️  First run failed, but continuing..."
}

# Generate report and optionally upload to GCS
CLASSIFICATION_PATH="/app/artifacts/milestones-assignments/classification.json"
if [[ -f "$CLASSIFICATION_PATH" ]]; then
  echo "📝 Generating report from $CLASSIFICATION_PATH"
  export REPORT_GCS_BUCKET="${REPORT_GCS_BUCKET:-nexusshield-prod-artifacts}"
  export SHORT_SHA="${SHORT_SHA:-$(git rev-parse --short HEAD 2>/dev/null || echo latest)}"
  python3 /app/scripts/monitoring/report_generator.py "$CLASSIFICATION_PATH" "/tmp/milestone-organizer-report.html" || echo "⚠️  Report generation failed"
  if [[ -n "${REPORT_GCS_BUCKET:-}" ]]; then
    echo "📤 Attempting upload to gs://${REPORT_GCS_BUCKET}/"
    python3 - <<'PY'
from google.cloud import storage
import os
bucket=os.environ.get('REPORT_GCS_BUCKET')
src='/tmp/milestone-organizer-report.html'
dest=f"milestone-organizer-report-{os.environ.get('SHORT_SHA','latest')}-{__import__('datetime').datetime.utcnow().strftime('%Y%m%dT%H%M%SZ')}.html"
try:
    client=storage.Client()
    client.bucket(bucket).blob(dest).upload_from_filename(src)
    print('✓ Uploaded report to gs://%s/%s' % (bucket,dest))
except Exception as e:
    print('ERROR uploading report:', e)
PY
  fi
else
  echo "ℹ️  Classification file not found at $CLASSIFICATION_PATH; skipping report generation"
fi

# Keep the container alive by waiting on metrics server
echo "✅ Milestone Organizer Cloud Run ready (metrics on :8080)"
wait $METRICS_PID
