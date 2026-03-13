#!/usr/bin/env bash
set -euo pipefail

# sync_gsm_to_k8s.sh
# Simple helper to copy secrets from Google Secret Manager into Kubernetes secrets.
# Usage:
#   ./sync_gsm_to_k8s.sh --project nexusshield-prod --namespace ops slack-webhook:k8s-slack-secret aws-credentials:k8s-aws-secret
# Each mapping is GSM_SECRET_NAME:K8S_SECRET_NAME

PROJECT="${PROJECT:-$(gcloud config get-value project 2>/dev/null || echo '')}"
NAMESPACE="${NAMESPACE:-ops}"

if [ -z "$PROJECT" ]; then
  echo "ERROR: GCP project not set. Pass --project or set gcloud default project." >&2
  exit 2
fi

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 [--project PROJECT] [--namespace NAMESPACE] gsm_secret:k8s_secret [...]" >&2
  exit 2
fi

# Parse optional flags
while [[ "$1" == --* ]]; do
  case "$1" in
    --project)
      PROJECT="$2"; shift 2;;
    --namespace)
      NAMESPACE="$2"; shift 2;;
    *) echo "Unknown flag: $1"; exit 2;;
  esac
done

for mapping in "$@"; do
  gsm_name=${mapping%%:*}
  k8s_name=${mapping##*:}
  if [ -z "$gsm_name" ] || [ -z "$k8s_name" ]; then
    echo "Invalid mapping: $mapping" >&2; continue
  fi

  echo "Fetching secret versions for GSM secret: $gsm_name (project: $PROJECT)"
  payload=$(gcloud secrets versions access latest --secret="$gsm_name" --project="$PROJECT" 2>/dev/null || true)
  if [ -z "$payload" ]; then
    echo "Failed to read GSM secret: $gsm_name" >&2
    continue
  fi

  # Create or replace k8s secret
  tmpfile=$(mktemp)
  printf "%s" "$payload" > "$tmpfile"

  # If payload is JSON, create as generic secret with keys
  if jq -e . >/dev/null 2>&1 <<<'$payload'; then
    # When payload is JSON, convert to key/value pairs
    kubectl -n "$NAMESPACE" create secret generic "$k8s_name" --from-file=creds.json="$tmpfile" --dry-run=client -o yaml | kubectl apply -f -
  else
    # Otherwise store as a single value under 'value'
    kubectl -n "$NAMESPACE" create secret generic "$k8s_name" --from-file=value="$tmpfile" --dry-run=client -o yaml | kubectl apply -f -
  fi

  rm -f "$tmpfile"
  echo "Synced GSM:$gsm_name -> k8s:$NAMESPACE/$k8s_name"
done

echo "Done."
