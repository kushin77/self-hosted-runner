#!/usr/bin/env bash
# credcache.sh - load encrypted local credential cache from /etc/nexusshield/credcache.enc
set -euo pipefail

CREDCACHE_FILE="/etc/nexusshield/credcache.enc"

load_credcache() {
    if [[ ! -f "${CREDCACHE_FILE}" ]]; then
        return 1
    fi
    if [[ -z "${CREDCACHE_PASSPHRASE:-}" ]]; then
        echo "[credcache] CREDCACHE_PASSPHRASE not set" >&2
        return 1
    fi

    # Decrypt to stdout and parse JSON
    local json
    json=$(openssl enc -d -aes-256-cbc -pbkdf2 -in "${CREDCACHE_FILE}" -pass pass:"${CREDCACHE_PASSPHRASE}" 2>/dev/null || true)
    if [[ -z "${json}" ]]; then
        echo "[credcache] Decryption failed or empty cache" >&2
        return 1
    fi

    # Use jq to extract values if available
    if command -v jq &>/dev/null; then
        export RUNNER_SSH_KEY=$(echo "${json}" | jq -r '.runner_ssh_key // empty')
        export RUNNER_SSH_USER=$(echo "${json}" | jq -r '.runner_ssh_user // empty')
        export DATABASE_SECRET=$(echo "${json}" | jq -r '.database_secret // empty')
    else
        # Fallback parsing (unsafe for complex JSON) — expect simple lines
        export RUNNER_SSH_KEY=$(echo "${json}" | grep -oP '(?<="runner_ssh_key"\s*:\s*").*(?=")' || true)
        export RUNNER_SSH_USER=$(echo "${json}" | grep -oP '(?<="runner_ssh_user"\s*:\s*").*(?=")' || true)
        export DATABASE_SECRET=$(echo "${json}" | grep -oP '(?<="database_secret"\s*:\s*").*(?=")' || true)
    fi

    return 0
}

export -f load_credcache
