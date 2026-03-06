#!/usr/bin/env bash
set -euo pipefail
# Fetch secrets from GCP Secret Manager and write them to files for CI consumption.
# Usage: gcp_fetch_secrets.sh <GCP_PROJECT> <KUBECONFIG_SECRET_NAME> <REGTOKEN_SECRET_NAME>

if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <GCP_PROJECT> <KUBECONFIG_SECRET_NAME> <REGTOKEN_SECRET_NAME>" >&2
  exit 2
fi

GCP_PROJECT=$1
KUBECONFIG_SECRET_NAME=$2
REGTOKEN_SECRET_NAME=$3

if [ -z "${GCP_SA_KEY:-}" ]; then
  echo "Missing required environment variable: GCP_SA_KEY (base64-encoded service account JSON)" >&2
  exit 3
fi

tmp_key="/tmp/gcp_sa_key.json"
echo "$GCP_SA_KEY" | base64 -d > "$tmp_key"
gcloud auth activate-service-account --key-file="$tmp_key" --project="$GCP_PROJECT"

fetch_secret() {
  secret_name="$1"
  gcloud secrets versions access latest --secret="$secret_name" --project="$GCP_PROJECT"
}

echo "Fetching kubeconfig secret: $KUBECONFIG_SECRET_NAME"
KUBECONFIG_BASE64=$(fetch_secret "$KUBECONFIG_SECRET_NAME")
echo "$KUBECONFIG_BASE64" > kubeconfig.b64

echo "Fetching registration token secret: $REGTOKEN_SECRET_NAME"
REG_TOKEN=$(fetch_secret "$REGTOKEN_SECRET_NAME")
echo "$REG_TOKEN" > regtoken.txt

echo "Wrote kubeconfig.b64 and regtoken.txt"
