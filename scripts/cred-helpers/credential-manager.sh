#!/usr/bin/env bash
set -euo pipefail
# Unified credential manager: tries specified layer or auto fallback (GSM -> Vault -> KMS)
# Usage: credential-manager.sh <credential-name> [retrieve-from] [cache-ttl-seconds]
NAME="${1:-}"
RETRIEVE_FROM="${2:-auto}"
CACHE_TTL="${3:-300}"
if [ -z "$NAME" ]; then
  echo "ERROR: credential-manager.sh requires credential name" >&2
  exit 2
fi
audit_id() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 12
  else
    echo "$(date +%s)-$$"
  fi
}
set_output(){
  # write key=value lines to stdout for composite action to capture
  echo "credential=$1"
  echo "cached=false"
  expires_at="$(date -u -d "+$CACHE_TTL seconds" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d "+$CACHE_TTL seconds" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "expires-at=$expires_at"
  echo "source-layer=$2"
  echo "audit-id=$(audit_id)"
}
fetch_and_output(){
  local layer="$1"
  local val
  if [ "$layer" = "gsm" ]; then
    if val=$(bash "$(dirname "$0")/fetch-from-gsm.sh" "$NAME"); then
      set_output "$val" gsm
      return 0
    fi
  elif [ "$layer" = "vault" ]; then
    if val=$(bash "$(dirname "$0")/fetch-from-vault.sh" "$NAME"); then
      set_output "$val" vault
      return 0
    fi
  elif [ "$layer" = "kms" ]; then
    if val=$(bash "$(dirname "$0")/fetch-from-kms.sh" "$NAME"); then
      set_output "$val" kms
      return 0
    fi
  fi
  return 1
}
if [ "$RETRIEVE_FROM" = "auto" ]; then
  # try GSM -> Vault -> KMS
  if fetch_and_output gsm; then exit 0; fi
  if fetch_and_output vault; then exit 0; fi
  if fetch_and_output kms; then exit 0; fi
  echo "ERROR: credential-manager: no provider returned secret for $NAME" >&2
  exit 2
else
  if fetch_and_output "$RETRIEVE_FROM"; then exit 0; fi
  echo "ERROR: credential-manager: provider $RETRIEVE_FROM failed for $NAME" >&2
  exit 2
fi
