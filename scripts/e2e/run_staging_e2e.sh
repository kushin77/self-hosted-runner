#!/usr/bin/env bash
set -euo pipefail

# Minimal E2E staging harness: provisions example KEDA module via Terraform.
# Usage: ./scripts/e2e/run_staging_e2e.sh [--auto-approve] [--capture-artifacts]

AUTO_APPROVE=0
CAPTURE_ARTIFACTS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --auto-approve) AUTO_APPROVE=1; shift ;;
    --capture-artifacts) CAPTURE_ARTIFACTS=1; shift ;;
    *) shift ;;
  esac
done

ROOT_DIR="$(cd "$(dirname "$0")/../../" && pwd)"
EXAMPLE_DIR="$ROOT_DIR/terraform/examples/keda-provision"

if [ ! -d "$EXAMPLE_DIR" ]; then
  echo "Example dir not found: $EXAMPLE_DIR" >&2
  exit 2
fi

pushd "$EXAMPLE_DIR" >/dev/null

export TF_IN_AUTOMATION=1

if [ ! -f .terraform.lock.hcl ]; then
  terraform init -input=false
else
  terraform init -input=false -upgrade
fi

if [ "$AUTO_APPROVE" -eq 1 ]; then
  terraform apply -auto-approve
else
  terraform plan -out=tfplan
fi

if [ "$CAPTURE_ARTIFACTS" -eq 1 ]; then
  mkdir -p "$ROOT_DIR/workflow-artifacts/e2e"
  terraform show -json > "$ROOT_DIR/workflow-artifacts/e2e/terraform_state.json" || true
fi

popd >/dev/null

echo "E2E staging harness complete"
