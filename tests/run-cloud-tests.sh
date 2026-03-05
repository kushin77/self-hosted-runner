#!/usr/bin/env bash
# Wrapper to prepare credentials and run all cloud tests
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Prepare creds from environment (will fail if required vars missing)
"${SCRIPT_DIR}/prepare-creds.sh"

# Ensure master runner is executable
chmod +x "${SCRIPT_DIR}/run-tests.sh"

# Run all cloud tests
"${SCRIPT_DIR}/run-tests.sh" --all
