#!/bin/bash
################################################################################
# Unit tests for Vault credential helper
# Tests missing args, missing env vars, and syntax validation
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT_HELPER="$SCRIPT_DIR/../cred-helpers/fetch-from-vault-real.sh"

echo "Testing Vault helper: $VAULT_HELPER"
echo "===================================="

# Test 1: Missing credential path argument
echo "Test 1: Missing credential path argument..."
if ! bash "$VAULT_HELPER" 2>&1 | grep -q "Usage\|secret_path\|required"; then
  if bash "$VAULT_HELPER" 2>/dev/null; then
    echo "FAIL: Expected non-zero exit"
    exit 1
  fi
fi
echo "✓ PASS: Missing arg handled correctly"

# Test 2: Missing VAULT_ADDR environment variable
echo "Test 2: Missing VAULT_ADDR environment variable..."
unset VAULT_ADDR 2>/dev/null || true
if bash "$VAULT_HELPER" secret/path 2>&1 | grep -q "VAULT_ADDR\|required\|not set"; then
  echo "✓ PASS: Missing env var handled correctly"
elif ! bash "$VAULT_HELPER" secret/path 2>/dev/null; then
  echo "✓ PASS: Missing env var exit code correct"
else
  echo "FAIL: Expected error handling for missing VAULT_ADDR"
  exit 1
fi

# Test 3: Syntax check
echo "Test 3: Syntax check..."
if bash -n "$VAULT_HELPER" 2>&1; then
  echo "✓ PASS: No syntax errors"
else
  echo "FAIL: Syntax error detected"
  exit 1
fi

echo ""
echo "All Vault helper tests passed! ✓"
