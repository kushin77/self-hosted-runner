#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WORKFLOWS_DIR="$ROOT_DIR/.github/workflows"

if [ -d "$WORKFLOWS_DIR" ]; then
  echo "ERROR: .github/workflows exists. The repository policy forbids GitHub Actions."
  echo "Found workflow files:" 
  ls -1 "$WORKFLOWS_DIR" || true
  exit 2
else
  echo "OK: No .github/workflows found. Repository complies with no-Actions policy."
  exit 0
fi
