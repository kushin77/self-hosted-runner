#!/usr/bin/env bash
set -euo pipefail
# Simple local test for credential-manager + GSM mock env var
export TEST_GSM_my_secret="supersecret-value-TEST"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bash "$SCRIPT_DIR/credential-manager.sh" my_secret gsm 120
