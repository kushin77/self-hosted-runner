#!/usr/bin/env bash
set -euo pipefail

# Create a venv and install requirements for local development/testing
VENV_DIR=${VENV_DIR:-.venv}
python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"
pip install --upgrade pip
pip install -r scripts/cloudrun/requirements.txt
echo "Dev environment ready. Activate with: source $VENV_DIR/bin/activate"
