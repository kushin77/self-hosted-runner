#!/usr/bin/env bash
set -euo pipefail

# Deploy runner SSH public key to self-hosted runner hosts (supports single host or batch)
# This script fetches the rotated ED25519 public key from GSM and installs it on runner hosts.
# Usage: ./deploy-runner-ssh-key.sh [--project=PROJECT] [--secret-name=SECRET] [--user=USER] [--hosts=HOST1,HOST2,...]
#
# Example (single host):
#   ./scripts/ops/deploy-runner-ssh-key.sh \
#     --project nexusshield-prod \
#     --secret-name runner-ssh-key-20260312194327 \
#     --user root \
#     --hosts 192.168.168.42
#
# Example (batch):
#   ./scripts/ops/deploy-runner-ssh-key.sh \
#     --project nexusshield-prod \
#     --secret-name runner-ssh-key-20260312194327 \
#     --user runner \
#     --hosts runner1.local,runner2.local,runner3.local

PROJECT="${PROJECT:-nexusshield-prod}"
SECRET_NAME="${SECRET_NAME:-runner-ssh-key-20260312194327}"
REMOTE_USER="${REMOTE_USER:-root}"
RUNNER_HOSTS="${RUNNER_HOSTS:-}"
SSH_PORT="${SSH_PORT:-22}"
SSH_DIR=".ssh"
SSH_KEYFILE="id_ed25519"
AUTHORIZED_KEYS="authorized_keys"

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --project PROJECT              GCP project (default: nexusshield-prod)
  --secret-name NAME             GSM secret name (default: runner-ssh-key-20260312194327)
  --user USER                    Remote SSH user (default: root)
  --hosts HOSTS                  Comma-separated list of hosts (e.g., host1,host2,host3, OR set RUNNER_HOSTS env var)
  --port PORT                    SSH port (default: 22)
  -h, --help                     Show this help

Environment Variables:
  PROJECT                        Same as --project
  SECRET_NAME                    Same as --secret-name
  REMOTE_USER                    Same as --user
  RUNNER_HOSTS                   Same as --hosts
  SSH_PORT                       Same as --port

Example:
  RUNNER_HOSTS=runner1,runner2 ./scripts/ops/deploy-runner-ssh-key.sh --project=nexusshield-prod --secret-name=runner-ssh-key-20260312194327
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project=*) PROJECT="${1#*=}"; shift;;
    --project) PROJECT="$2"; shift 2;;
    --secret-name=*) SECRET_NAME="${1#*=}"; shift;;
    --secret-name) SECRET_NAME="$2"; shift 2;;
    --user=*) REMOTE_USER="${1#*=}"; shift;;
    --user) REMOTE_USER="$2"; shift 2;;
    --hosts=*) RUNNER_HOSTS="${1#*=}"; shift;;
    --hosts) RUNNER_HOSTS="$2"; shift 2;;
    --port=*) SSH_PORT="${1#*=}"; shift;;
    --port) SSH_PORT="$2"; shift 2;;
    -h|--help) usage;;
    *) echo "Unknown argument: $1"; usage;;
  esac
done

if [[ -z "$RUNNER_HOSTS" ]]; then
  echo "ERROR: --hosts or RUNNER_HOSTS env var required"
  usage
fi

# Fetch private key from GSM
echo "📥 Fetching $SECRET_NAME from GSM (project: $PROJECT)"
TMPKEY="$(mktemp)"
trap "rm -f $TMPKEY" EXIT

if ! gcloud secrets versions access latest --secret="$SECRET_NAME" --project="$PROJECT" > "$TMPKEY" 2>/dev/null; then
  echo "❌ Failed to fetch secret. Ensure you have GSM access and the secret exists."
  exit 1
fi

chmod 600 "$TMPKEY"

# Derive public key
echo "🔑 Deriving public key"
PUBKEY="$(ssh-keygen -y -f "$TMPKEY" 2>/dev/null)"

if [[ -z "$PUBKEY" ]]; then
  echo "❌ Failed to derive public key from secret."
  exit 1
fi

echo "✅ Public key: ${PUBKEY:0:50}... (truncated)"

# Deploy to each host
IFS=',' read -ra HOSTS <<< "$RUNNER_HOSTS"
for host in "${HOSTS[@]}"; do
  host="${host//[[:space:]]/}"  # trim whitespace
  if [[ -z "$host" ]]; then
    continue
  fi

  echo ""
  echo "🚀 Deploying to $REMOTE_USER@$host:$SSH_PORT"

  # 1. Ensure SSH directory exists with correct perms
  if ! ssh -p "$SSH_PORT" "$REMOTE_USER@$host" "mkdir -p ~/$SSH_DIR && chmod 700 ~/$SSH_DIR" 2>/dev/null; then
    echo "⚠️  Could not create $SSH_DIR on $host (skipping)"
    continue
  fi

  # 2. Check if key already authorized
  if ssh -p "$SSH_PORT" "$REMOTE_USER@$host" "grep -qxF '$PUBKEY' ~/$SSH_DIR/$AUTHORIZED_KEYS 2>/dev/null" 2>/dev/null; then
    echo "ℹ️  Key already authorized on $host"
  else
    # 3. Append public key
    if echo "$PUBKEY" | ssh -p "$SSH_PORT" "$REMOTE_USER@$host" "cat >> ~/$SSH_DIR/$AUTHORIZED_KEYS && chmod 600 ~/$SSH_DIR/$AUTHORIZED_KEYS" 2>/dev/null; then
      echo "✅ Key deployed to $host"
    else
      echo "❌ Failed to deploy key to $host"
    fi
  fi
done

echo ""
echo "✅ Deployment complete. Runners can now authenticate using the rotated SSH key."
echo "📝 Audit: Public key deployed on $(date -u +'%FT%TZ')"
