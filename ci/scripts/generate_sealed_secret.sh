#!/usr/bin/env bash
set -euo pipefail

# generate_sealed_secret.sh
# Usage: see help below. This script creates a Kubernetes Secret YAML (dry-run),
# seals it with kubeseal and writes a SealedSecret YAML. It does not store
# plaintext secrets in the repository.

usage(){
  cat <<EOF
Usage: $0 --name NAME --namespace NAMESPACE --key KEY --value VALUE --out FILE [--controller-namespace ns] [--cert-file path]

Options:
  --name                Secret name (default: vault-approle-secret)
  --namespace           Kubernetes namespace (default: gitops)
  --key                 Key name inside the secret (default: secretId)
  --value               Secret value (supply as env or stdin to avoid logs)
  --out                 Output file path for sealed secret
  --controller-namespace  Namespace where sealed-secrets controller lives (default: kube-system)
  --cert-file           Optional kubeseal public cert file path (safer for CI usage)
  --help                Show this help
EOF
}

NAME="vault-approle-secret"
NAMESPACE="gitops"
KEY="secretId"
OUT="sealed-vault-approle-secret.yaml"
CONTROLLER_NS="kube-system"
CERT_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) NAME="$2"; shift 2;;
    --namespace) NAMESPACE="$2"; shift 2;;
    --key) KEY="$2"; shift 2;;
    --value) VALUE="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    --controller-namespace) CONTROLLER_NS="$2"; shift 2;;
    --cert-file) CERT_FILE="$2"; shift 2;;
    --help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 2;;
  esac
done

if [[ -z "${VALUE-}" ]]; then
  echo "ERROR: --value must be provided (sensitive)." >&2
  exit 2
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

SECRET_YAML="$TMPDIR/secret.yaml"

kubectl create secret generic "$NAME" \
  --namespace "$NAMESPACE" \
  --from-literal="$KEY=$VALUE" \
  --dry-run=client -o yaml > "$SECRET_YAML"

if [[ -n "$CERT_FILE" ]]; then
  kubeseal --cert "$CERT_FILE" --format yaml < "$SECRET_YAML" > "$OUT"
else
  kubeseal --controller-namespace "$CONTROLLER_NS" --controller-name sealed-secrets --format yaml < "$SECRET_YAML" > "$OUT"
fi

echo "Wrote sealed secret to: $OUT"
