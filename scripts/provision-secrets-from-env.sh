#!/usr/bin/env bash
set -euo pipefail

# provision-secrets-from-env.sh
# Idempotent helper to provision required deployment fields from environment variables
# into GSM (gcloud), Vault (vault CLI), AWS Secrets Manager (aws cli), and GitHub
# repository secrets (gh). Operators should run this on a machine authenticated to
# the respective provider CLIs (gcloud, vault, aws, gh).

REPO="kushin77/self-hosted-runner"

log(){ echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*"; }

ensure_gsm_secret(){
  local name="$1" value="$2"
  if ! command -v gcloud &>/dev/null; then
    log "gcloud not available; skipping GSM provisioning for $name"
    return 0
  fi
  if gcloud secrets describe "$name" >/dev/null 2>&1; then
    log "Updating GSM secret: $name"
    echo -n "$value" | gcloud secrets versions add "$name" --data-file=- >/dev/null
  else
    log "Creating GSM secret: $name"
    echo -n "$value" | gcloud secrets create "$name" --data-file=- >/dev/null
  fi
}

ensure_vault_secret(){
  local path="$1" value="$2"
  if ! command -v vault &>/dev/null; then
    log "vault not available; skipping Vault provisioning for $path"
    return 0
  fi
  log "Writing Vault: $path"
  vault kv put "$path" value="$value" >/dev/null
}

ensure_aws_secret(){
  local name="$1" value="$2"
  if ! command -v aws &>/dev/null; then
    log "aws CLI not available; skipping AWS Secrets Manager for $name"
    return 0
  fi
  if aws secretsmanager describe-secret --secret-id "$name" >/dev/null 2>&1; then
    log "Updating AWS secret: $name"
    aws secretsmanager put-secret-value --secret-id "$name" --secret-string "$value" >/dev/null
  else
    log "Creating AWS secret: $name"
    aws secretsmanager create-secret --name "$name" --secret-string "$value" >/dev/null
  fi
}

ensure_github_secret(){
  local key="$1" value="$2"
  if ! command -v gh &>/dev/null; then
    log "gh CLI not available; skipping GitHub secret $key"
    return 0
  fi
  echo -n "$value" | gh secret set "$key" --repo "$REPO" >/dev/null
  log "GitHub secret set: $key"
}

set_if_present(){
  local envvar="$1" provider_name="$2"
  local val="${!envvar:-}"
  if [ -n "$val" ]; then
    case "$provider_name" in
      gsm)
        ensure_gsm_secret "$envvar" "$val" ;;
      vault)
        # write to secret path secret/deployment/fields/<ENVVAR>
        ensure_vault_secret "secret/deployment/fields/${envvar}" "$val" ;;
      aws)
        ensure_aws_secret "deployment/${envvar}" "$val" ;;
      gh)
        ensure_github_secret "$envvar" "$val" ;;
      *) log "unknown provider target: $provider_name" ;;
    esac
  else
    log "Env var $envvar not set; skipping"
  fi
}

main(){
  log "Provisioning required deployment fields from environment variables"

  # Fields to provision: VAULT_ADDR, VAULT_ROLE, AWS_ROLE_TO_ASSUME, GCP_WORKLOAD_IDENTITY_PROVIDER
  set_if_present VAULT_ADDR gsm
  set_if_present VAULT_ADDR vault
  set_if_present VAULT_ADDR gh

  set_if_present VAULT_ROLE vault
  set_if_present VAULT_ROLE gh

  set_if_present AWS_ROLE_TO_ASSUME aws
  set_if_present AWS_ROLE_TO_ASSUME gh

  set_if_present GCP_WORKLOAD_IDENTITY_PROVIDER gsm
  set_if_present GCP_WORKLOAD_IDENTITY_PROVIDER gh

  # Runner SSH credentials
  set_if_present RUNNER_SSH_KEY aws
  set_if_present RUNNER_SSH_KEY gsm
  set_if_present RUNNER_SSH_KEY gh

  set_if_present RUNNER_SSH_USER gh
  set_if_present RUNNER_SSH_USER gsm

  log "Provisioning complete"
}

main "$@"
