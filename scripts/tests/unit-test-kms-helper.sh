#!/bin/bash
################################################################################
# Unit tests for KMS credential helper
# Tests missing args, missing env vars, and syntax validation
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KMS_HELPER="$SCRIPT_DIR/../cred-helpers/fetch-from-kms-real.sh"

echo "Testing KMS helper: $KMS_HELPER"
echo "================================="

# Test 1: Missing secret name argument
echo "Test 1: Missing secret name argument..."
if ! bash "$KMS_HELPER" 2>&1 | grep -q "Usage\|secret_name\|required"; then
  if bash "$KMS_HELPER" 2>/dev/null; then
    echo "FAIL: Expected non-zero exit"
    exit 1
  fi
fi
echo "✓ PASS: Missing arg handled correctly"

# Test 2: Missing AWS_KMS_KEY_ID environment variable
echo "Test 2: Missing AWS_KMS_KEY_ID environment variable..."
unset AWS_KMS_KEY_ID 2>/dev/null || true
if bash "$KMS_HELPER" test-secret 2>&1 | grep -q "AWS_KMS_KEY_ID\|required\|not set"; then
  echo "✓ PASS: Missing env var handled correctly"
elif ! bash "$KMS_HELPER" test-secret 2>/dev/null; then
  echo "✓ PASS: Missing env var exit code correct"
else
  echo "FAIL: Expected error handling for missing AWS_KMS_KEY_ID"
  exit 1
fi

# Test 3: Syntax check
echo "Test 3: Syntax check..."
if bash -n "$KMS_HELPER" 2>&1; then
  echo "✓ PASS: No syntax errors"
else
  echo "FAIL: Syntax error detected"
  exit 1
fi

echo ""
echo "All KMS helper tests passed! ✓"
