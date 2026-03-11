#!/usr/bin/env bash
set -euo pipefail

################################################################################
# Idempotent operator bootstrap for secrets orchestration
# - Runs Terraform if infra/*.tf exists (idempotent)
# - Prints required repository secret names
# - Supports --apply to actually provision resources
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_MARKER="$ROOT_DIR/.infra_secrets_orchestration_provisioned"

DRY_RUN=1
if [ "${1:-}" = "--apply" ] || [ "${APPLY:-}" = "1" ]; then
    DRY_RUN=0
fi

usage() {
    cat <<EOF
Usage: $0 [--apply] [--force]

This script is idempotent. Without --apply it only prints the plan and
required repository secrets. With --apply it will attempt to run any
Terraform in infra/ and create a marker file on success. Use --force to
re-run provisioning even if previously marked.

Required repository secrets (ensure these are set before running health):
- GCP_PROJECT_ID
- GCP_WORKLOAD_ID_PROVIDER
- AWS_KMS_KEY_ID
- VAULT_ADDR
- VAULT_TOKEN (or use external auth)
EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    usage
    exit 0
fi

FORCE=0
for arg in "$@"; do
    if [ "$arg" = "--force" ]; then
        FORCE=1
    fi
done

if [ -f "$STATE_MARKER" ] && [ "$FORCE" -ne 1 ]; then
    echo "Provisioning already recorded in $STATE_MARKER. Use --force to re-run."
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "Dry-run: exiting."; exit 0
    fi
fi

echo "Operator bootstrap: idempotent setup for secrets orchestration"

pushd "$ROOT_DIR" >/dev/null

if compgen -G "infra/*.tf" >/dev/null; then
    if ! command -v terraform >/dev/null 2>&1; then
        echo "terraform not found in PATH; please install Terraform or run provider-specific steps manually." >&2
        popd >/dev/null
        exit 2
    fi

    echo "Found Terraform templates under infra/ — running idempotent apply"
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "DRY-RUN: terraform init && terraform plan (no changes applied)"
        pushd infra >/dev/null
        terraform init -input=false >/dev/null || true
        terraform plan -input=false || true
        popd >/dev/null
    else
        pushd infra >/dev/null
        terraform init -input=false
        terraform apply -auto-approve -input=false
        popd >/dev/null
        touch "$STATE_MARKER"
        echo "Provisioning complete; recorded marker $STATE_MARKER"
    fi
else
    echo "No Terraform templates found under infra/. If you use other provisioning tools, run them now." 
fi

popd >/dev/null

echo "Operator checklist reminders:"
echo "- Ensure required repo secrets are set (see usage)"
echo "- If GitHub Actions API is unavailable, run infra/local_secrets_health_check.sh locally and attach logs to the issue"

exit 0
