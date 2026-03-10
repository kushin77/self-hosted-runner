#!/usr/bin/env bash
set -euo pipefail

# deploy-direct.sh
# Idempotent, direct-deploy helper for running the compose stack on the remote host.
# This performs a secure copy of runtime artifacts and triggers an atomic compose restart.

REMOTE_USER=${REMOTE_USER:-akushnir}
REMOTE_HOST=${REMOTE_HOST:-192.168.168.42}
REMOTE_DIR=${REMOTE_DIR:-/home/${REMOTE_USER}/self-hosted-runner}
COMPOSE_FILE=${COMPOSE_FILE:-docker-compose.phase6.yml}

usage(){
  cat <<EOF
Usage: $0 [--no-build]

Environment variables:
  REMOTE_USER REMOTE_HOST REMOTE_DIR COMPOSE_FILE

This script is idempotent: it uploads updated files, pulls images, and starts
the stack with --remove-orphans to clean up old services.
EOF
}

NO_BUILD=0
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --no-build) NO_BUILD=1; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 2;;
  esac
done

echo "Deploying to ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}"

LIBDIR="$(cd "$(dirname "$0")/.." && pwd)/lib"
if [ -f "${LIBDIR}/deploy-common.sh" ]; then
  # Use centralized deploy helpers (idempotent + auditable)
  source "${LIBDIR}/deploy-common.sh"
  deploy_upload_payload "${COMPOSE_FILE}" "${REMOTE_USER}" "${REMOTE_HOST}" "${REMOTE_DIR}"
  deploy_execute_remote "${COMPOSE_FILE}" "${REMOTE_USER}" "${REMOTE_HOST}" "${REMOTE_DIR}" ${NO_BUILD}
  echo "Deploy completed via deploy-common.sh"
else
  # Fallback to embedded transport (legacy)
  tar -C $(dirname "$COMPOSE_FILE") -czf /tmp/compose_payload.tgz $(basename "$COMPOSE_FILE") || true
  scp /tmp/compose_payload.tgz ${REMOTE_USER}@${REMOTE_HOST}:/tmp/ || true

  ssh ${REMOTE_USER}@${REMOTE_HOST} bash -s <<'EOF'
set -euo pipefail
cd ${REMOTE_DIR}
tar xzf /tmp/compose_payload.tgz -C .
rm -f /tmp/compose_payload.tgz

# Pull latest images and restart the stack in an idempotent fashion
if [ "${NO_BUILD}" -eq 0 ]; then
  docker-compose -f ${COMPOSE_FILE} pull || true
  docker-compose -f ${COMPOSE_FILE} up -d --build --remove-orphans || true
else
  docker-compose -f ${COMPOSE_FILE} pull || true
  docker-compose -f ${COMPOSE_FILE} up -d --remove-orphans || true
fi

# Wait for health stabilization (short)
sleep 5
docker-compose -f ${COMPOSE_FILE} ps
EOF

  echo "Deploy completed (check remote for service statuses)."
fi
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
