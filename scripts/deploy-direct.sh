#!/usr/bin/env bash
set -euo pipefail
# Direct, idempotent deploy helper (SSH + docker-compose)
# Usage: ./scripts/deploy-direct.sh <user@host> [compose-file]

TARGET=${1:-}
COMPOSE_FILE=${2:-docker-compose.phase6.yml}

if [ -z "$TARGET" ]; then
  echo "Usage: $0 user@host [compose-file]" >&2
  exit 2
fi

RELEASE_TAG=$(git rev-parse --short HEAD || echo "local")
ARCHIVE="/tmp/repo-${RELEASE_TAG}.tar.gz"

echo "Packaging repo..."
git archive --format=tar HEAD | gzip > /tmp/repo-${RELEASE_TAG}.tar.gz

echo "Uploading to ${TARGET}:${ARCHIVE} and running remote deploy"
scp /tmp/repo-${RELEASE_TAG}.tar.gz "${TARGET}:${ARCHIVE}"
ssh "${TARGET}" bash -s <<EOF
set -euo pipefail
mkdir -p ~/deployments/${RELEASE_TAG}
tar -xzf ${ARCHIVE} -C ~/deployments/${RELEASE_TAG}
cd ~/deployments/${RELEASE_TAG}
# Ensure .env is present (secrets should be provisioned via Vault/GSM)
if [ ! -f .env ]; then
  echo ".env not found on target. Abort." >&2
  exit 3
fi
# Pull images and run compose on target (idempotent)
docker-compose -f "${COMPOSE_FILE}" pull || true
docker-compose -f "${COMPOSE_FILE}" up -d --remove-orphans --build
EOF

echo "Deploy triggered on ${TARGET} (release ${RELEASE_TAG})"
rm -f /tmp/repo-${RELEASE_TAG}.tar.gz
