#!/usr/bin/env bash
set -euo pipefail

# rotate-uptime-token.sh
# Generates a new uptime token, stores it as a new Secret Manager version,
# and updates Cloud Run services to reference the latest secret version.
#
# Usage:
# DRY_RUN=1 ./scripts/ops/rotate-uptime-token.sh --project=nexusshield-prod --region=us-central1 --services=nexus-shield-portal-backend,nexus-shield-portal-frontend

PROG_NAME="$(basename "$0")"

print_usage() {
  cat <<EOF
Usage: $PROG_NAME [--project=PROJECT] [--region=REGION] [--services=svc1,svc2] [--secret=SECRET_NAME]

Environment:
  DRY_RUN=1   Print commands instead of executing them

Defaults:
  PROJECT: nexusshield-prod
  REGION: us-central1
  SERVICES: nexus-shield-portal-backend,nexus-shield-portal-frontend
  SECRET: uptime-check-token

This script is idempotent and safe to run repeatedly. It creates a new secret
version in Secret Manager and updates Cloud Run services to reference
the latest secret version using `gcloud run services update --update-secrets`.
EOF
}

PROJECT="nexusshield-prod"
REGION="us-central1"
SERVICES="nexus-shield-portal-backend,nexus-shield-portal-frontend"
SECRET_NAME="uptime-check-token"

for arg in "$@"; do
  case "$arg" in
    --project=*) PROJECT=${arg#*=} ;; 
    --region=*) REGION=${arg#*=} ;;
    --services=*) SERVICES=${arg#*=} ;;
    --secret=*) SECRET_NAME=${arg#*=} ;;
    -h|--help) print_usage; exit 0 ;;
    *) echo "Unknown arg: $arg" >&2; print_usage; exit 2 ;;
  esac
done

DRY_RUN=${DRY_RUN:-0}

run() {
  if [ "$DRY_RUN" = "1" ]; then
    echo "+ $*"
  else
    echo "-> Running: $*"
    eval "$*"
  fi
}

# Generate a 48-char URL-safe alphanumeric token.
generate_token() {
  # Use openssl to generate random bytes, base64, then strip non-alnum and truncate
  local t
  t=$(openssl rand -base64 48 2>/dev/null | tr -dc 'A-Za-z0-9' | head -c48)
  echo "$t"
}

main() {
  echo "[rotate-uptime-token] project=$PROJECT region=$REGION secret=$SECRET_NAME services=$SERVICES"

  TOKEN=$(generate_token)

  if [ -z "$TOKEN" ]; then
    echo "Failed to generate token" >&2
    exit 1
  fi

  # Add new secret version
  echo "[rotate-uptime-token] Adding new secret version to Secret Manager: $SECRET_NAME"
  run "printf '%s' \"$TOKEN\" | gcloud secrets versions add $SECRET_NAME --data-file=- --project=$PROJECT"

  # Update each Cloud Run service to reference the latest secret version
  IFS=',' read -r -a svcs <<< "$SERVICES"
  for svc in "${svcs[@]}"; do
    svc_trimmed=$(echo "$svc" | xargs)
    if [ -z "$svc_trimmed" ]; then
      continue
    fi
    echo "[rotate-uptime-token] Updating Cloud Run service: $svc_trimmed to use $SECRET_NAME:latest"
    run "gcloud run services update $svc_trimmed --region=$REGION --project=$PROJECT --update-secrets=UPTIME_CHECK_TOKEN=$SECRET_NAME:latest"
  done

  echo "[rotate-uptime-token] Rotation complete. New secret version added and services updated."
  if [ "$DRY_RUN" = "1" ]; then
    echo "Note: DRY_RUN=1 — no changes were made. Re-run without DRY_RUN to apply." 
  fi
}

main "$@"
