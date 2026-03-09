#!/usr/bin/env bash
set -euo pipefail

# provision-credentials.sh
# Idempotent helper to provision an SSH deploy key and user to one of:
#  - gsm  (Google Secret Manager)
#  - vault (HashiCorp Vault KV)
#  - kms  (AWS Secrets Manager)
#
# Usage:
#  ./scripts/provision-credentials.sh <provider> <ssh-key-file> [ssh-user] [secret-name]
#
# Examples:
#  ./scripts/provision-credentials.sh gsm /tmp/deploy-key.pem deploy runner-ssh-key
#  ./scripts/provision-credentials.sh vault /tmp/deploy-key.pem deploy runner-deploy
#  ./scripts/provision-credentials.sh kms /tmp/deploy-key.pem deploy runner/ssh-credentials

PROVIDER="${1:-}"
SSH_KEY_FILE="${2:-}"
SSH_USER="${3:-akushnir}"
SECRET_NAME="${4:-runner-ssh-key}"

if [[ -z "$PROVIDER" || -z "$SSH_KEY_FILE" ]]; then
  echo "Usage: $0 <provider:gsm|vault|kms> <ssh-key-file> [ssh-user] [secret-name]"
  exit 2
fi

if [[ ! -f "$SSH_KEY_FILE" ]]; then
  echo "SSH key file not found: $SSH_KEY_FILE"
  exit 3
fi

set -x

case "${PROVIDER,,}" in
  gsm)
    # Create secret if missing, then add a new version
    if ! gcloud secrets describe "$SECRET_NAME" >/dev/null 2>&1; then
      gcloud secrets create "$SECRET_NAME" --replication-policy="automatic"
    fi
    gcloud secrets versions add "$SECRET_NAME" --data-file="$SSH_KEY_FILE"
    # Also store ssh_user as separate secret (idempotent)
    if ! gcloud secrets describe "${SECRET_NAME}-user" >/dev/null 2>&1; then
      printf "%s" "$SSH_USER" | gcloud secrets create "${SECRET_NAME}-user" --replication-policy="automatic" --data-file=- >/dev/null 2>&1 || true
    else
      printf "%s" "$SSH_USER" | gcloud secrets versions add "${SECRET_NAME}-user" --data-file=- >/dev/null 2>&1 || true
    fi
    ;;

  vault)
    # Requires VAULT_ADDR and auth configured
    # Store both ssh_key and ssh_user under secret path
    vault kv put "${SECRET_NAME}" ssh_key=@"${SSH_KEY_FILE}" ssh_user="$SSH_USER"
    ;;

  kms|aws)
    # AWS Secrets Manager: create or update secret
    if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" >/dev/null 2>&1; then
      aws secretsmanager put-secret-value --secret-id "$SECRET_NAME" --secret-string file://<(jq -n --arg key "$(base64 -w0 < "$SSH_KEY_FILE")" --arg user "$SSH_USER" '{ssh_key:$key,ssh_user:$user}')
    else
      aws secretsmanager create-secret --name "$SECRET_NAME" --secret-string "$(jq -n --arg key "$(base64 -w0 < "$SSH_KEY_FILE")" --arg user "$SSH_USER" '{ssh_key:$key,ssh_user:$user}')"
    fi
    ;;

  *)
    echo "Unsupported provider: $PROVIDER"; exit 4 ;;
esac

echo "Credentials provisioned to $PROVIDER (secret: $SECRET_NAME)"
