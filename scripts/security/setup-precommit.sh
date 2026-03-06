#!/usr/bin/env bash
set -euo pipefail

# Install pre-commit and initialize detect-secrets baseline
if ! command -v pre-commit >/dev/null 2>&1; then
  echo "Installing pre-commit..."
  pip3 install --user pre-commit
fi

echo "Installing pre-commit hooks..."
pre-commit install

if [ ! -f .secrets.baseline ]; then
  echo "Creating detect-secrets baseline (you may need to review the baseline)..."
  pre-commit run detect-secrets --all-files || true
  pre-commit run --hook-stage manual detect-secrets --all-files || true
fi

echo "Pre-commit setup complete. Run 'pre-commit run --all-files' to test."