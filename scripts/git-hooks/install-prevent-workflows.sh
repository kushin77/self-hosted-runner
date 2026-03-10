#!/usr/bin/env bash
set -euo pipefail

# Install and enable the prevent-workflows pre-commit hook for this repo
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "${PWD}")
HOOK_DIR="${REPO_ROOT}/.githooks"
HOOK_FILE="${HOOK_DIR}/prevent-workflows"

if [ ! -f "${HOOK_FILE}" ]; then
  echo "Hook not found: ${HOOK_FILE}" >&2
  exit 2
fi

chmod +x "${HOOK_FILE}"

# Configure repo to use the .githooks directory for hooks
git config core.hooksPath ".githooks"

echo "Installed prevent-workflows hook and set core.hooksPath=.githooks"

exit 0
