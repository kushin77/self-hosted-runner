#!/usr/bin/env bash
set -euo pipefail
# Login to container registry (internal). Expects REGISTRY_URL, REGISTRY_USERNAME, REGISTRY_PASSWORD env vars.

if [[ -z "${REGISTRY_URL:-}" || -z "${REGISTRY_USERNAME:-}" || -z "${REGISTRY_PASSWORD:-}" ]]; then
  echo "REGISTRY_URL, REGISTRY_USERNAME and REGISTRY_PASSWORD must be set"
  exit 2
fi

echo "Logging into ${REGISTRY_URL}..."
echo "${REGISTRY_PASSWORD}" | docker login "${REGISTRY_URL}" --username "${REGISTRY_USERNAME}" --password-stdin
echo "Login successful"
