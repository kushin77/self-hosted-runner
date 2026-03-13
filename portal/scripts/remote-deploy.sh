#!/usr/bin/env bash
set -euo pipefail

# Remote deploy helper - rsync subtree to worker, fetch secrets, and bring up compose stack.
# Requirements on the worker: docker, docker-compose, gcloud or vault CLI (if using GSM/Vault).

WORKER=${1:-}
if [[ -z "$WORKER" ]]; then
  echo "Usage: $0 user@worker-host" >&2
  exit 1
fi

LOCAL_DIR=$(cd "$(dirname "$0")/.." && pwd)
REMOTE_DIR="/home/$(echo "$WORKER" | cut -d@ -f1)/self-hosted-runner/portal"

echo "Syncing portal subtree to $WORKER:$REMOTE_DIR"
rsync -az --delete --exclude node_modules --exclude dist --exclude .pnpm-store --exclude .git "$LOCAL_DIR"/ "$WORKER":"$REMOTE_DIR"/

echo "Fetching secrets on remote (GSM/Vault) and using an ephemeral env file for docker-compose"
ssh "$WORKER" bash -s <<'SSHEND'
set -euo pipefail
cd ~/self-hosted-runner/portal/docker

# Build a temporary env file from either GSM or Vault. Keys sourced from .env.production if present,
# otherwise from .env.example. The script writes into .env.tmp and uses it for docker compose, then
# securely deletes it.
TMP_ENV=.env.tmp
: > "$TMP_ENV"

KEYFILE=.env.production
if [[ ! -f "$KEYFILE" ]]; then
  KEYFILE=.env.example
fi

if command -v gcloud >/dev/null 2>&1; then
  echo "Using gcloud to fetch secrets"
  while IFS='=' read -r key _; do
    key=$(echo "$key" | tr -d ' ')
    [[ -z "$key" || "$key" =~ ^# ]] && continue
    if value=$(gcloud secrets versions access latest --secret="portal/${key}" 2>/dev/null); then
      printf '%s=%s\n' "$key" "$value" >> "$TMP_ENV"
    fi
  done < "$KEYFILE"
elif command -v vault >/dev/null 2>&1; then
  echo "Using Vault to fetch secrets"
  while IFS='=' read -r key _; do
    key=$(echo "$key" | tr -d ' ')
    [[ -z "$key" || "$key" =~ ^# ]] && continue
    # Try to read common kv path secret/portal/<key>
    if value=$(vault kv get -field=value secret/portal/${key} 2>/dev/null || true); then
      if [[ -n "$value" && "$value" != "null" ]]; then
        printf '%s=%s\n' "$key" "$value" >> "$TMP_ENV"
      fi
    fi
  done < "$KEYFILE"
else
  echo "No GSM or Vault CLI found on worker; ensure secrets are provisioned or run the deploy with secrets pre-created" >&2
fi

if [[ -s "$TMP_ENV" ]]; then
  chmod 600 "$TMP_ENV" || true
  echo "Starting docker-compose with ephemeral env file"
  docker compose pull || true
  docker compose --env-file "$TMP_ENV" up -d --build
  docker compose ps
  shred -u "$TMP_ENV" || rm -f "$TMP_ENV"
else
  echo "No secrets fetched to $TMP_ENV; running docker compose without env-file (will use defaults)." >&2
  docker compose pull || true
  docker compose up -d --build
  docker compose ps
fi
SSHEND

echo "Remote deploy finished. Run ./portal/docker/smoke-check.sh <worker-host> locally to verify." 

# Automated smoke-check and audit logging
HOST_ONLY=$(echo "$WORKER" | cut -d@ -f2)
REPO_ROOT=$(dirname "$(cd "$LOCAL_DIR" && pwd)/..")
SMOKE_CHECK_SCRIPT="$LOCAL_DIR/../portal/docker/smoke-check.sh"

if [[ -x "$SMOKE_CHECK_SCRIPT" ]]; then
  echo "Running smoke-check against $HOST_ONLY"
  if "$SMOKE_CHECK_SCRIPT" "$HOST_ONLY"; then
    TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    printf '%s\n' "{ \"timestamp\": \"$TS\", \"action\": \"deploy\", \"service\": \"portal\", \"host\": \"$HOST_ONLY\", \"status\": \"success\", \"actor\": \"automation-agent\" }" >> "$REPO_ROOT/audit-trail.jsonl"
    (cd "$REPO_ROOT" && git add audit-trail.jsonl && git commit -m "audit: portal deploy to $HOST_ONLY - success" || true && git push || true)
    echo "Smoke-check passed and audit recorded."
  else
    TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    printf '%s\n' "{ \"timestamp\": \"$TS\", \"action\": \"deploy\", \"service\": \"portal\", \"host\": \"$HOST_ONLY\", \"status\": \"failure\", \"actor\": \"automation-agent\" }" >> "$REPO_ROOT/audit-trail.jsonl"
    (cd "$REPO_ROOT" && git add audit-trail.jsonl && git commit -m "audit: portal deploy to $HOST_ONLY - failure" || true && git push || true)
    echo "Smoke-check FAILED; audit recorded." >&2
    exit 2
  fi
else
  echo "Smoke-check script not found or not executable: $SMOKE_CHECK_SCRIPT" >&2
fi
