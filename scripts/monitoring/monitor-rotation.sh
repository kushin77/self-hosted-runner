#!/bin/bash
# Monitor Credential Rotation Execute in Real-time
# This script watches the credential rotation system and provides live updates
# Usage: bash monitor-rotation.sh

PROJECT="nexusshield-prod"
LOCATION="us-central1"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  CREDENTIAL ROTATION SYSTEM — LIVE MONITORING DASHBOARD        ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

while true; do
  clear
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║  CREDENTIAL ROTATION SYSTEM — LIVE MONITORING DASHBOARD        ║"
  echo "║  Updated: $(date '+%Y-%m-%d %H:%M:%S UTC')                     ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""
  
  # Cloud Scheduler Status
  echo "📅 CLOUD SCHEDULER STATUS"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  gcloud scheduler jobs describe credential-rotation-daily \
    --location="$LOCATION" \
    --project="$PROJECT" \
    --format='table(state,schedule,lastExecutionTime)' 2>/dev/null || echo "Error fetching scheduler status"
  echo ""
  
  # Recent Build Status
  echo "🔨 RECENT CLOUD BUILDS"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  gcloud builds list \
    --project="$PROJECT" \
    --limit=3 \
    --format='table(id,status,createTime)' 2>/dev/null || echo "Error fetching builds"
  echo ""
  
  # Current Credential Versions
  echo "📊 CURRENT CREDENTIAL VERSIONS"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  printf "%-20s %s\n" "GitHub Token:" "v$(gcloud secrets versions list github-token --project="$PROJECT" --limit=1 --format='value(name)' 2>/dev/null)"
  printf "%-20s %s\n" "AWS Access Key:" "v$(gcloud secrets versions list aws-access-key-id --project="$PROJECT" --limit=1 --format='value(name)' 2>/dev/null)"
  printf "%-20s %s\n" "AWS Secret Key:" "v$(gcloud secrets versions list aws-secret-access-key --project="$PROJECT" --limit=1 --format='value(name)' 2>/dev/null)"
  printf "%-20s %s\n" "Vault Address:" "v$(gcloud secrets versions list VAULT_ADDR --project="$PROJECT" --limit=1 --format='value(name)' 2>/dev/null)"
  printf "%-20s %s\n" "Vault Token:" "v$(gcloud secrets versions list VAULT_TOKEN --project="$PROJECT" --limit=1 --format='value(name)' 2>/dev/null)"
  echo ""
  
  # Pub/Sub Topic Stats
  echo "📨 PUB/SUB TOPIC STATUS"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  gcloud pubsub topics describe credential-rotation-trigger \
    --project="$PROJECT" \
    --format='table(name.basename(),messageStoragePolicy.allowedPersistenceRegions)' 2>/dev/null || echo "Error fetching topic status"
  echo ""
  
  echo "⏱️  Refreshing in 10 seconds... (Press Ctrl+C to exit)"
  sleep 10
done
