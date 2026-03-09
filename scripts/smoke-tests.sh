#!/bin/bash
set -euo pipefail

echo "=== smoke-tests: starting ==="
PASS=0
FAIL=0

check_file() {
  local p="$1"
  if [[ -f "$p" ]]; then
    echo "OK: file exists: $p"
    PASS=$((PASS+1))
  else
    echo "MISSING: $p"
    FAIL=$((FAIL+1))
  fi
}

check_cmd() {
  local cmd="$1"
  if command -v $cmd >/dev/null 2>&1; then
    echo "OK: command available: $cmd"
    PASS=$((PASS+1))
  else
    echo "MISSING: command: $cmd"
    FAIL=$((FAIL+1))
  fi
}

# Check expected files from the Vault Agent integration
check_file "/opt/self-hosted-runner/scripts/identity/vault-agent/vault-agent.hcl"
check_file "/opt/self-hosted-runner/scripts/identity/vault-agent/registry-creds.tpl"
check_file "/opt/self-hosted-runner/scripts/identity/vault-agent/vault-agent.service"

# Check runner startup wrapper presence
check_file "/opt/self-hosted-runner/scripts/identity/runner-startup.sh"

# Check vault binary presence (not required to be running)
check_cmd "vault"

echo "--- summary: PASS=$PASS FAIL=$FAIL ---"

if [[ $FAIL -ne 0 ]]; then
  echo "SMOKE TESTS: FAILED"
  exit 2
fi

echo "SMOKE TESTS: OK"
exit 0
