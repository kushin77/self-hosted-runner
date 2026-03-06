#!/usr/bin/env bash
set -euo pipefail

# create_sealedsecret.sh
# Create a Kubernetes Secret with the runner registration token and optionally
# create a SealedSecret using 'kubeseal' (requires kubeseal and the cluster's
# SealedSecrets controller public key). This is useful to store the sealed
# secret in Git (encrypted) and apply during install.
# Usage: ./scripts/ci/create_sealedsecret.sh <REG_TOKEN> [NAMESPACE] [OUTPUT_FILE]

REG_TOKEN=${1:-}
NAMESPACE=${2:-gitlab-runner}
OUT_FILE=${3:-sealed-gitlab-runner-secret.yaml}

if [ -z "$REG_TOKEN" ]; then
  echo "Usage: $0 <REG_TOKEN> [NAMESPACE] [OUTPUT_FILE]"
  exit 1
fi

echo "Creating Kubernetes Secret manifest (dry-run apply)"
kubectl -n "$NAMESPACE" create secret generic gitlab-runner-regtoken --from-literal=registrationToken="$REG_TOKEN" --dry-run=client -o yaml > /tmp/gitlab-runner-secret.yaml

if command -v kubeseal >/dev/null 2>&1; then
  echo "Sealing secret with kubeseal..."
  kubeseal --format yaml < /tmp/gitlab-runner-secret.yaml > "$OUT_FILE"
  echo "SealedSecret written to $OUT_FILE - safe to commit to repo (still verify)."
  rm -f /tmp/gitlab-runner-secret.yaml
else
  echo "kubeseal not found — writing plain Secret manifest to $OUT_FILE (do NOT commit real tokens)."
  mv /tmp/gitlab-runner-secret.yaml "$OUT_FILE"
fi
