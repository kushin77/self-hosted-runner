#!/usr/bin/env bash
set -euo pipefail

# Request a certificate from Vault PKI and write to disk for Envoy.
# Requires: `vault` CLI authenticated (e.g., via Vault Agent or VAULT_TOKEN env var).

VAULT_ADDR="${VAULT_ADDR:-https://vault.example.local}"
ROLE=${ROLE:-control-plane-role}
COMMON_NAME=${COMMON_NAME:-control-plane.example.local}
OUT_DIR=${OUT_DIR:-/etc/envoy/tls}

mkdir -p "$OUT_DIR"

echo "Requesting certificate for $COMMON_NAME from $VAULT_ADDR (role $ROLE)"
resp=$(vault write -format=json "$VAULT_ADDR/v1/pki/issue/$ROLE" common_name="$COMMON_NAME" ttl="72h")
cert=$(echo "$resp" | jq -r .data.certificate)
key=$(echo "$resp" | jq -r .data.private_key)
ca=$(echo "$resp" | jq -r .data.issuing_ca)

echo "$cert" > "$OUT_DIR/server.crt"
echo "$key" > "$OUT_DIR/server.key"
echo "$ca" > "$OUT_DIR/ca.crt"

chmod 640 "$OUT_DIR"/*
echo "Wrote certs to $OUT_DIR"
