#!/usr/bin/env bash
set -euo pipefail

# remove_github_workflows.sh
# Deletes any GitHub Actions workflow files under .github/workflows

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOWS_DIR="${REPO_ROOT}/.github/workflows"

if [[ -d "${WORKFLOWS_DIR}" ]]; then
    echo "Removing GitHub Actions workflows in ${WORKFLOWS_DIR}"
    rm -rf "${WORKFLOWS_DIR}"
    # write an immutable marker
    mkdir -p "${REPO_ROOT}/.github"
    echo "NO_WORKFLOWS" > "${REPO_ROOT}/.github/WORKFLOWS_DISABLED"
    echo "Workflows removed. Commit the change if desired."
    exit 0
else
    echo "No workflows directory present; nothing to do."
    exit 0
fi
