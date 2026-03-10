#!/usr/bin/env bash
set -euo pipefail

# scripts/rotate-secrets.sh
# Rotate POSTGRES_DSN in Vault or Google Secret Manager and update remote .env atomically.
# Usage: --mode <vault|gsm> --secret-name <name> [--remote-user user] [--remote-host host]

MODE=""
SECRET_NAME="nexusshield-postgres-dsn"
REMOTE_USER=${REMOTE_USER:-akushnir}
REMOTE_HOST=${REMOTE_HOST:-192.168.168.42}
REMOTE_DIR=${REMOTE_DIR:-/home/${REMOTE_USER}/self-hosted-runner}
SKIP_PUSH=0

usage(){
  cat <<EOF
Usage: $0 --mode <vault|gsm> [--secret-name <secret>] [--skip-push]

Examples:
  # Vault mode (operator session must be authenticated to Vault):
  ./scripts/rotate-secrets.sh --mode vault --secret-name nexusshield-postgres-dsn

  # GSM mode (requires GOOGLE_APPLICATION_CREDENTIALS in env):
  ./scripts/rotate-secrets.sh --mode gsm --secret-name nexusshield-postgres-dsn
EOF
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --mode) MODE="$2"; shift 2;;
    --secret-name) SECRET_NAME="$2"; shift 2;;
    --skip-push) SKIP_PUSH=1; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 2;;
  esac
done

if [ -z "$MODE" ]; then
  usage; exit 2
fi

log(){
  echo "[rotate-secrets] $*"
}

fetch_from_vault(){
  # Expect operator to be authenticated with the `vault` CLI (vault login)
  if ! command -v vault >/dev/null 2>&1 ; then
    echo "vault CLI not available"; return 1
  fi
  log "Fetching secret from Vault (via vault CLI): $SECRET_NAME"
  # Use kv v2 path; adjust if your Vault layout differs
  vault kv get -field=dsn secret/${SECRET_NAME} 2>/dev/null || true
}

fetch_from_gsm(){
  if [ -z "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]; then
    echo "GOOGLE_APPLICATION_CREDENTIALS not set"; return 1
  fi
  log "Fetching secret from GSM: $SECRET_NAME"
  gcloud secrets versions access latest --secret=${SECRET_NAME} --format='get(payload.data)' | base64 --decode || true
}

get_dsn=""
case "$MODE" in
  vault)
    get_dsn=$(fetch_from_vault)
    ;;
  gsm)
    get_dsn=$(fetch_from_gsm)
    ;;
  *) echo "Unknown mode: $MODE"; exit 3;;
esac

if [ -z "$get_dsn" ]; then
  echo "Failed to retrieve DSN"; exit 4
fi

# Atomically update remote .env
log "Updating .env on ${REMOTE_HOST}:${REMOTE_DIR}"
ssh ${REMOTE_USER}@${REMOTE_HOST} bash -s <<REMOTE_EOF
set -euo pipefail
cd "${REMOTE_DIR}"
TMP=\$(mktemp)
trap 'rm -f "\$TMP"' EXIT
cat > "\$TMP" <<ENV
# NexusShield Portal MVP — Provisioned Secrets
# Rotated: \$(date -u +"%Y-%m-%dT%H:%M:%SZ")
POSTGRES_DSN=${get_dsn}
ENV
mv "\$TMP" .env
chmod 600 .env
echo ".env rotated"
REMOTE_EOF

log "Rotation complete"

if [ "$SKIP_PUSH" -eq 0 ]; then
  # Commit audit entry locally and push (immutable trail)
  AUDIT_FILE="logs/rotate-secrets-$(date +%s).jsonl"
  mkdir -p logs
  echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\", \"action\": \"rotate-secrets\", \"mode\": \"$MODE\", \"secret\": \"$SECRET_NAME\" }" >> "$AUDIT_FILE"
  git add "$AUDIT_FILE" || true
  git commit -m "audit(secrets): rotate $SECRET_NAME via $MODE" || true
  git push origin main || true
fi

log "Done"
