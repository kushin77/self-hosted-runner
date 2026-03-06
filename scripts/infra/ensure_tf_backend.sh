#!/usr/bin/env bash
set -euo pipefail

# ensure_tf_backend.sh - quick check for recommended remote backend
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TF_DIR="$ROOT_DIR/terraform"

if [ ! -d "$TF_DIR" ]; then
  echo "No terraform directory found. Skipping backend check."; exit 0
fi

pushd "$TF_DIR" >/dev/null
if grep -R "backend \"s3\"" -n . >/dev/null 2>&1 || grep -R "backend \"azurerm\"" -n . >/dev/null 2>&1; then
  echo "OK: remote backend configured"
  exit 0
else
  echo "WARN: no remote backend configured. See terraform/backend.s3.example.tf for example." >&2
  exit 1
fi
popd >/dev/null
