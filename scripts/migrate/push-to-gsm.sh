#!/usr/bin/env bash
set -euo pipefail
# Push secret to Google Secret Manager (dry-run safe)
# Usage: push-to-gsm.sh --name NAME --value VALUE [--dry-run]

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
AUDIT_FILE="$AUDIT_DIR/gsm-$(date -u +%Y%m%dT%H%M%SZ).jsonl"

if [ "$DRY_RUN" = true ]; then
  echo "DRY-RUN: GSM create secret $NAME"
  printf '{"time":"%s","provider":"gsm","name":"%s","action":"create","status":"dry-run"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$NAME" >> "$AUDIT_FILE"
  exit 0
fi

if ! command -v gcloud >/dev/null 2>&1; then
  echo "gcloud not available" >&2
  printf '{"time":"%s","provider":"gsm","name":"%s","action":"create","status":"error","error":"gcloud-missing"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$NAME" >> "$AUDIT_FILE"
  exit 2
fi

# idempotent create: try to add, if exists update
if gcloud secrets describe "$NAME" >/dev/null 2>&1; then
  echo "Secret $NAME exists — adding new version"
  echo -n "$VALUE" | base64 | gcloud secrets versions add "$NAME" --data-file=- >/dev/null
  status=updated
else
  echo -n "$VALUE" | base64 | gcloud secrets create "$NAME" --data-file=- >/dev/null
  status=created
fi

printf '{"time":"%s","provider":"gsm","name":"%s","action":"create","status":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$NAME" "$status" >> "$AUDIT_FILE"
echo "OK: $status $NAME"
