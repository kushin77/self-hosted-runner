#!/usr/bin/env bash
set -euo pipefail

# Delete compute instances with label 'runner=ephemeral' older than TTL (hours)
# Usage: ./scripts/cleanup/cleanup_ephemeral_runners.sh <project> <zone> <ttl-hours>

PROJECT=${1:-}
ZONE=${2:-}
TTL_HOURS=${3:-24}

if [ -z "$PROJECT" ] || [ -z "$ZONE" ]; then
  echo "Usage: $0 <project> <zone> <ttl-hours>"
  exit 2
fi

THRESHOLD=$(date -u -d "-$TTL_HOURS hours" +%Y-%m-%dT%H:%M:%SZ)

# List instances with label and creation timestamp
gcloud compute instances list --project="$PROJECT" --zones="$ZONE" --filter="labels.runner=ephemeral" --format='value(name,creationTimestamp)' | while read -r NAME CREATED; do
  if [[ "$CREATED" < "$THRESHOLD" ]]; then
    echo "Deleting instance $NAME (created: $CREATED)"
    gcloud compute instances delete "$NAME" --zone="$ZONE" --project="$PROJECT" --quiet || true
  fi
done

echo "Cleanup run complete."
