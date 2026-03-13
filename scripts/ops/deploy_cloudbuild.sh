#!/usr/bin/env bash
set -euo pipefail

# deploy_cloudbuild.sh
# Triggers a Cloud Build for direct deployment using a build config in the repo.
# Requires: gcloud CLI authenticated with proper project and permissions.

PROJECT=${PROJECT:-nexusshield-prod}
BUILD_CONFIG=${BUILD_CONFIG:-cloudbuild.nexus-phase0.yaml}
SUBSTITUTIONS=${SUBSTITUTIONS:-}

usage(){
  cat <<EOF
Usage: $0 --project PROJECT [--config FILE] [--substitutions KEY=VAL,...]

This script triggers Cloud Build with repository sources.
Secrets are fetched from Google Secret Manager at runtime in the Cloud Build config.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="$2"; shift 2;;
    --config) BUILD_CONFIG="$2"; shift 2;;
    --substitutions) SUBSTITUTIONS="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 1;;
  esac
done

echo "Triggering Cloud Build in project=$PROJECT using config=$BUILD_CONFIG"

if [[ -n "$SUBSTITUTIONS" ]]; then
  gcloud builds submit --project="$PROJECT" --config="$BUILD_CONFIG" --substitutions="$SUBSTITUTIONS"
else
  gcloud builds submit --project="$PROJECT" --config="$BUILD_CONFIG"
fi

echo "Build submitted. Monitor with: gcloud builds list --project=$PROJECT or gcloud builds log BUILD_ID --project=$PROJECT"
