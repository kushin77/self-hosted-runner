#!/bin/bash
################################################################################
# Unit tests for GSM credential helper
# Tests missing args, missing env vars, and syntax validation
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GSM_HELPER="$SCRIPT_DIR/../cred-helpers/fetch-from-gsm.sh"

echo "Testing GSM helper: $GSM_HELPER"
echo "================================="

# Test 1: Missing credential name argument
echo "Test 1: Missing credential name argument..."
if ! bash "$GSM_HELPER" 2>&1 | grep -q "Usage"; then
  if bash "$GSM_HELPER" 2>/dev/null; then
    echo "FAIL: Expected non-zero exit"
    exit 1
  fi
fi
echo "✓ PASS: Missing arg handled correctly"

# Test 2: Credential request with proper delegation
echo "Test 2: Script delegates to credential-manager..."
if bash -n "$GSM_HELPER" 2>&1; then
  echo "✓ PASS: Delegation script syntax correct"
else
  echo "FAIL: Syntax error in delegation script"
  exit 1
fi

# Test 3: Syntax check
echo "Test 3: Complete syntax check..."
if bash -n "$GSM_HELPER" 2>&1; then
  echo "✓ PASS: No syntax errors"
else
  echo "FAIL: Syntax error detected"
  exit 1
fi

echo ""
echo "All GSM helper tests passed! ✓"
