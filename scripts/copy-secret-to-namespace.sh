#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 3 ]; then
  echo "Usage: $0 <secret-name> <from-namespace> <to-namespace>"
  exit 2
fi

SECRET_NAME="$1"
FROM_NS="$2"
TO_NS="$3"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to run this script. Install jq and retry."
  exit 1
fi

echo "Copying secret '$SECRET_NAME' from namespace '$FROM_NS' to namespace '$TO_NS'..."

# Read secret JSON, strip cluster-assigned metadata, set target namespace, and apply
kubectl get secret "$SECRET_NAME" -n "$FROM_NS" -o json \
  | jq 'del(.metadata.uid, .metadata.resourceVersion, .metadata.creationTimestamp, .metadata.selfLink, .metadata.managedFields) | .metadata.namespace = "'"$TO_NS"'"' \
  | kubectl apply -f -

echo "Done."
