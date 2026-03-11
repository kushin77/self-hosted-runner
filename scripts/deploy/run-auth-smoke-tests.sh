#!/usr/bin/env bash
# Authenticated post-deploy smoke tests for Cloud Run services
# Usage:
#   ./run-auth-smoke-tests.sh --services backend,frontend --impersonate svc-account@project.iam.gserviceaccount.com
#   ./run-auth-smoke-tests.sh --services backend --key-file /path/to/key.json

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${PWD}/logs/epic5-smoke"
mkdir -p "$LOG_DIR"
OUT="$LOG_DIR/auth-smoke-$(date -u +%FT%TZ).log"

SERVICES="nexus-shield-portal-backend,nexus-shield-portal-frontend"
IMP_SERVICE_ACCOUNT=""
KEY_FILE=""
GCP_PROJECT="nexusshield-prod"
GCP_REGION="us-central1"

usage(){
  cat <<EOF
Usage: $0 [--services svc1,svc2] [--impersonate SERVICE_ACCOUNT] [--key-file PATH] [--project PROJECT] [--region REGION]

Examples:
  $0 --impersonate my-ci@project.iam.gserviceaccount.com
  $0 --key-file /secrets/sa.json --services nexus-shield-portal-backend
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --services) SERVICES="$2"; shift 2;;
    --impersonate) IMP_SERVICE_ACCOUNT="$2"; shift 2;;
    --key-file) KEY_FILE="$2"; shift 2;;
    --project) GCP_PROJECT="$2"; shift 2;;
    --region) GCP_REGION="$2"; shift 2;;
    -h|--help) usage;;
    *) echo "Unknown arg: $1"; usage;;
  esac
done

echo "Authenticated smoke tests started at $(date -u +%FT%TZ)" > "$OUT"

activate_auth(){
  if [ -n "$IMP_SERVICE_ACCOUNT" ]; then
    echo "Impersonating service account: $IMP_SERVICE_ACCOUNT" >> "$OUT"
    # no-ops if environment already supports impersonation
    export CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT="$IMP_SERVICE_ACCOUNT"
  elif [ -n "$KEY_FILE" ]; then
    echo "Activating service account key: $KEY_FILE" >> "$OUT"
    gcloud auth activate-service-account --key-file="$KEY_FILE" --project="$GCP_PROJECT" >> "$OUT" 2>&1 || true
  else
    echo "No impersonation or keyfile provided — attempting current gcloud auth context" >> "$OUT"
  fi
}

get_url(){
  local svc="$1"
  gcloud run services describe "$svc" --platform managed --project "$GCP_PROJECT" --region "$GCP_REGION" --format='value(status.url)' 2>/dev/null || echo ""
}

get_id_token(){
  local url="$1"
  if [ -n "$IMP_SERVICE_ACCOUNT" ]; then
    gcloud auth print-identity-token --impersonate-service-account="$IMP_SERVICE_ACCOUNT" --audiences="$url" 2>/dev/null || true
  elif [ -n "$KEY_FILE" ]; then
    gcloud auth print-identity-token --audiences="$url" 2>/dev/null || true
  else
    gcloud auth print-identity-token --audiences="$url" 2>/dev/null || true
  fi
}

run_check(){
  local svc="$1"
  echo "--- Service: $svc ---" >> "$OUT"
  url=$(get_url "$svc")
  if [ -z "$url" ]; then
    echo "Service $svc URL not found" >> "$OUT"
    return 2
  fi
  echo "URL: $url" >> "$OUT"
  token=$(get_id_token "$url")
  if [ -z "$token" ]; then
    echo "Failed to obtain identity token for $svc" >> "$OUT"
    return 3
  fi
  echo "Calling $url/health" >> "$OUT"
  http_code=$(curl -sS -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $token" -m 10 "$url/health" || echo "000")
  echo "HTTP_CODE:$http_code" >> "$OUT"
  if [ "$http_code" = "200" ]; then
    echo "$svc: OK" >> "$OUT"
    return 0
  else
    echo "$svc: FAIL (HTTP $http_code)" >> "$OUT"
    return 4
  fi
}

activate_auth

IFS=','; for svc in $SERVICES; do
  svc_trimmed=$(echo "$svc" | xargs)
  run_check "$svc_trimmed"
done

echo "Authenticated smoke tests completed at $(date -u +%FT%TZ)" >> "$OUT"
echo "Logs: $OUT"

exit 0
