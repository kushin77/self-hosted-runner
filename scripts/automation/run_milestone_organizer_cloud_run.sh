#!/bin/bash
# Startup script for Cloud Run: metrics server + periodic organizer execution
set -euo pipefail

echo "🚀 Milestone Organizer Cloud Run Startup ($(date -u +'%Y-%m-%dT%H:%M:%SZ'))"

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
/bin/bash /app/scripts/automation/run_milestone_organizer_v2.sh || {
  echo "⚠️  First run failed, but continuing..."
}

# Keep the container alive by waiting on metrics server
echo "✅ Milestone Organizer Cloud Run ready (metrics on :8080)"
wait $METRICS_PID
