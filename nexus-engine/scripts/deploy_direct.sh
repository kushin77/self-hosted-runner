#!/usr/bin/env bash
set -euo pipefail
# Minimal direct-deploy helper.
# Expectations:
# - Operator environment has Docker and a container registry login method available.
# - Credentials are retrieved from GSM, Vault, or KMS and exported into env vars used below.
# - No GitHub Actions or PR-based release required — run locally on an operator host.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

IMAGE=${IMAGE:-"gcr.io/my-project/nexus-ingestion"}
TAG=${TAG:-"latest"}

# Helper: try Vault then GCP Secret Manager if present
fetch_secret() {
  name="$1"
  if command -v vault >/dev/null 2>&1 && [ -n "${VAULT_ADDR:-}" ]; then
    vault kv get -field=value "$name" || return 1
  elif command -v gcloud >/dev/null 2>&1; then
    gcloud secrets versions access latest --secret="$name" || return 1
  else
    return 1
  fi
}

echo "Building Go binary..."
mkdir -p bin
GOOS=${GOOS:-linux} GOARCH=${GOARCH:-amd64} go build -o "bin/ingestion" ./cmd/ingestion || {
  echo "go build failed" >&2
  exit 2
}

echo "Building container image $IMAGE:$TAG"
docker build -t "$IMAGE:$TAG" .

echo "Pushing image"
docker push "$IMAGE:$TAG"

echo "Deployment image pushed: $IMAGE:$TAG"
echo "Operator: deploy the image to your runtime (Cloud Run, GKE, ECS) using your normal infra tooling."

exit 0
