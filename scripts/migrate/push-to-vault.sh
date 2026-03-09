#!/usr/bin/env bash
set -euo pipefail
# Push secret to Vault KV (dry-run safe)
# Usage: push-to-vault.sh --name NAME --value VALUE [--mount secret] [--dry-run]

DRY_RUN=false
NAME=""
VALUE=""
MOUNT=${MOUNT:-secret}
while [ "$#" -gt 0 ]; do
  case "$1" in
    --name) NAME="$2"; shift 2;;
    --value) VALUE="$2"; shift 2;;
    --mount) MOUNT="$2"; shift 2;;
    --dry-run) DRY_RUN=true; shift;;
    -h|--help) echo "Usage: $0 --name NAME --value VALUE [--mount secret] [--dry-run]"; exit 0;;
    *) echo "Unknown arg: $1"; exit 2;;
  esac
done

if [ -z "$NAME" ]; then echo "--name required" >&2; exit 2; fi
if [ -z "$VALUE" ]; then echo "--value required" >&2; exit 2; fi

AUDIT_DIR=".migration-audit"
mkdir -p "$AUDIT_DIR"
AUDIT_FILE="$AUDIT_DIR/vault-$(date -u +%Y%m%dT%H%M%SZ).jsonl"

if [ "$DRY_RUN" = true ]; then
  echo "DRY-RUN: Vault write $MOUNT/data/$NAME"
  printf '{"time":"%s","provider":"vault","name":"%s","mount":"%s","action":"write","status":"dry-run"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$NAME" "$MOUNT" >> "$AUDIT_FILE"
  exit 0
fi

if [ -z "${VAULT_ADDR-}" ] || [ -z "${VAULT_TOKEN-}" ]; then
  echo "VAULT_ADDR or VAULT_TOKEN not set" >&2
  printf '{"time":"%s","provider":"vault","name":"%s","mount":"%s","action":"write","status":"error","error":"vault-cred-missing"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$NAME" "$MOUNT" >> "$AUDIT_FILE"
  exit 2
fi

# idempotent write to KV v2
DATA_FILE=$(mktemp)
jq -n --arg v "$VALUE" '{data: {value: $v}}' > "$DATA_FILE"
curl -sS --header "X-Vault-Token: $VAULT_TOKEN" --request POST "$VAULT_ADDR/v1/$MOUNT/data/$NAME" --data @"$DATA_FILE" >/dev/null
rm -f "$DATA_FILE"

printf '{"time":"%s","provider":"vault","name":"%s","mount":"%s","action":"write","status":"ok"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$NAME" "$MOUNT" >> "$AUDIT_FILE"
echo "OK: vault write $MOUNT/data/$NAME"
