#!/usr/bin/env bash
set -euo pipefail

# verify-rotation.sh
# Publishes a rotate message to Pub/Sub and verifies a new secret version is created.
# Returns 0 on success, non-zero on failure.

PROJECT=${PROJECT:-nexusshield-prod}
TOPIC=${TOPIC:-rotate-uptime-token-topic}
SECRET=${SECRET:-uptime-check-token}
WAIT_SECONDS=${WAIT_SECONDS:-20}

echo "[verify-rotation] project=$PROJECT topic=$TOPIC secret=$SECRET"

before_count=$(gcloud secrets versions list "$SECRET" --project="$PROJECT" --format="value(name)" | wc -l)
echo "[verify-rotation] secret versions before: $before_count"

echo "[verify-rotation] publishing rotate message to Pub/Sub"
gcloud pubsub topics publish "$TOPIC" --project="$PROJECT" --message='{"action":"rotate","test":"true"}' >/dev/null

echo "[verify-rotation] waiting $WAIT_SECONDS seconds for rotation"
sleep "$WAIT_SECONDS"

after_count=$(gcloud secrets versions list "$SECRET" --project="$PROJECT" --format="value(name)" | wc -l)
echo "[verify-rotation] secret versions after: $after_count"

if [ "$after_count" -gt "$before_count" ]; then
  echo "[verify-rotation] SUCCESS: secret version incremented"
  exit 0
else
  echo "[verify-rotation] FAILURE: secret version did not increment" >&2
  exit 2
fi
