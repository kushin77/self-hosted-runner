#!/usr/bin/env bash
set -euo pipefail
# Push secret to AWS Secrets Manager / KMS-wrapped store (dry-run safe)
# Usage: push-to-kms.sh --name NAME --value VALUE [--dry-run]

DRY_RUN=false
NAME=""
VALUE=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --name) NAME="$2"; shift 2;;
    --value) VALUE="$2"; shift 2;;
    --dry-run) DRY_RUN=true; shift;;
    -h|--help) echo "Usage: $0 --name NAME --value VALUE [--dry-run]"; exit 0;;
    *) echo "Unknown arg: $1"; exit 2;;
  esac
done

if [ -z "$NAME" ]; then echo "--name required" >&2; exit 2; fi
if [ -z "$VALUE" ]; then echo "--value required" >&2; exit 2; fi

AUDIT_DIR=".migration-audit"
mkdir -p "$AUDIT_DIR"
AUDIT_FILE="$AUDIT_DIR/kms-$(date -u +%Y%m%dT%H%M%SZ).jsonl"

if [ "$DRY_RUN" = true ]; then
  echo "DRY-RUN: AWS SecretsManager create $NAME"
  printf '{"time":"%s","provider":"kms","name":"%s","action":"create","status":"dry-run"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$NAME" >> "$AUDIT_FILE"
  exit 0
fi

if ! command -v aws >/dev/null 2>&1; then
  echo "aws CLI not available" >&2
  printf '{"time":"%s","provider":"kms","name":"%s","action":"create","status":"error","error":"aws-missing"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$NAME" >> "$AUDIT_FILE"
  exit 2
fi

# idempotent: create or update
if aws secretsmanager describe-secret --secret-id "$NAME" >/dev/null 2>&1; then
  aws secretsmanager put-secret-value --secret-id "$NAME" --secret-string "$VALUE" >/dev/null
  status=updated
else
  aws secretsmanager create-secret --name "$NAME" --secret-string "$VALUE" >/dev/null
  status=created
fi

printf '{"time":"%s","provider":"kms","name":"%s","action":"create","status":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$NAME" "$status" >> "$AUDIT_FILE"
echo "OK: $status $NAME"
