#!/bin/bash
set -euo pipefail

# Usage: ./scripts/build_and_push_runner.sh <gcr-project-id>
PROJECT=${1:-}
if [ -z "$PROJECT" ]; then
  echo "Usage: $0 <gcr-project-id>" >&2
  exit 2
fi

SHORT_SHA=$(git rev-parse --short HEAD)
IMAGE="gcr.io/${PROJECT}/milestone-organizer-runner:${SHORT_SHA}"

docker build -t "$IMAGE" images/milestone-organizer-runner
gcloud auth configure-docker --quiet
docker push "$IMAGE"
echo "Pushed: $IMAGE"
