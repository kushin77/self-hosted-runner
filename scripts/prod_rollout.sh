#!/usr/bin/env bash
set -euo pipefail

# Minimal, idempotent production rollout helper for provisioner-worker.
# Expects the following environment variables to be set (via CI secrets or env):
# - REGISTRY_URL (e.g. registry.example.com)
# - IMAGE_NAME (e.g. provisioner-worker)
# - IMAGE_TAG (e.g. prod-p2-<tag>)
# - VAULT_ADDR, VAULT_ROLE_ID, VAULT_SECRET_ID (for tests)
# - PROVISIONER_REDIS_URL

echo "Starting prod rollout helper"

if [ -z "${REGISTRY_URL:-}" ] || [ -z "${IMAGE_NAME:-}" ] || [ -z "${IMAGE_TAG:-}" ]; then
  echo "ERROR: REGISTRY_URL, IMAGE_NAME and IMAGE_TAG must be provided" >&2
  exit 2
fi

IMAGE_REF="${REGISTRY_URL%/}/${IMAGE_NAME}:${IMAGE_TAG}"

echo "Building image ${IMAGE_REF}"
docker build -t "${IMAGE_REF}" -f build/github-runner/Dockerfile .

if [ -n "${REGISTRY_USER:-}" ] && [ -n "${REGISTRY_TOKEN:-}" ]; then
  echo "Logging into registry ${REGISTRY_URL}"
  echo "${REGISTRY_TOKEN}" | docker login "${REGISTRY_URL}" -u "${REGISTRY_USER}" --password-stdin
fi

echo "Pushing image ${IMAGE_REF}"
docker push "${IMAGE_REF}"

echo "Image pushed: ${IMAGE_REF}"

# Lightweight smoke test: if managed-auth url provided, attempt to enqueue a test job
if [ -n "${MANAGED_AUTH_URL:-}" ]; then
  echo "Running smoke test against managed-auth at ${MANAGED_AUTH_URL}"
  set +e
  resp=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${MANAGED_AUTH_URL}/internal/test-provision" -H "Content-Type: application/json" -d '{"test":true}')
  set -e
  if [ "$resp" -ge 200 ] && [ "$resp" -lt 300 ]; then
    echo "Smoke test accepted (HTTP ${resp})"
  else
    echo "Smoke test returned HTTP ${resp}; please inspect managed-auth logs" >&2
    # Do not fail deployment; make it observable
  fi
fi

echo "Rollout helper completed (idempotent)."
