#!/usr/bin/env bash
# scripts/lib/validate_env.sh — Runtime environment variable validation
# Source this in every deployment/credential script to ensure required env vars are present
# and conform to standardized naming conventions (see SECRETS_NAMING_STANDARD.md)

set -euo pipefail

# Validate secret name against standard pattern
# Pattern: ^(CREDENTIAL|SECRET|TOKEN|KEY|APIKEY)_[A-Z]+_[A-Z]+_[A-Z]+(_[A-Z]+)?$
validate_secret_name() {
  local name="$1"
  if [[ ! "$name" =~ ^(CREDENTIAL|SECRET|TOKEN|KEY|APIKEY)_[A-Z_]+_[A-Z_]+(_[A-Z_]+)?$ ]]; then
    echo "[validate_env] ERROR: Secret name '$name' does not match standard naming convention" >&2
    echo "[validate_env]        Expected: PREFIX_PROVIDER_SYSTEM_TYPE_ENVIRONMENT[_QUALIFIER]" >&2
    return 1
  fi
  return 0
}

# Validate that required environment variables are set
# Usage: validate_required_env VAR1 VAR2 VAR3 || exit 1
validate_required_env() {
  local missing=()
  local invalid=()
  
  for var in "$@"; do
    # Check if var is set
    if [[ -z "${!var:-}" ]]; then
      missing+=("$var")
    fi
    
    # Validate naming convention (if it looks like a secret)
    if [[ "$var" =~ ^(CREDENTIAL|SECRET|TOKEN|KEY|APIKEY) ]]; then
      if ! validate_secret_name "$var"; then
        invalid+=("$var")
      fi
    fi
  done
  
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "[validate_env] ERROR: Missing required environment variables:" >&2
    printf '[validate_env]   - %s\n' "${missing[@]}" >&2
    echo "[validate_env] Fetch from GSM/Vault via: source scripts/lib/load_credentials.sh" >&2
    return 1
  fi
  
  if [[ ${#invalid[@]} -gt 0 ]]; then
    echo "[validate_env] ERROR: Invalid secret naming convention:" >&2
    printf '[validate_env]   - %s\n' "${invalid[@]}" >&2
    echo "[validate_env] See SECRETS_NAMING_STANDARD.md for naming rules" >&2
    return 1
  fi
  
  return 0
}

# Audit environment variable access (immutable logging)
audit_env_access() {
  local var_name="$1"
  local action="${2:-read}"
  local source="${3:-unknown}"
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local audit_dir=".env-audit"
  
  mkdir -p "$audit_dir"
  
  # Append to immutable audit log (never modify, always append)
  cat >> "$audit_dir/env-access-$(date +%Y%m%d).jsonl" <<EOF
{"timestamp":"$timestamp","event":"env_access","variable":"$var_name","action":"$action","source":"$source","script":"${BASH_SOURCE[0]}","pid":$$,"immutable":true}
EOF
}

# Check if secret should be fetched (not already in environment)
should_fetch_secret() {
  local var_name="$1"
  
  # If already set and non-empty, don't fetch again (idempotent)
  if [[ -n "${!var_name:-}" ]]; then
    audit_env_access "$var_name" "cached"
    return 1  # Don't fetch
  fi
  
  return 0  # Do fetch
}

export -f validate_secret_name
export -f validate_required_env
export -f audit_env_access
export -f should_fetch_secret
