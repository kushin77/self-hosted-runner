#!/bin/bash
################################################################################
# Unit tests for GSM credential helper
# Tests missing args, missing env vars, and syntax validation
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GSM_HELPER="$SCRIPT_DIR/../cred-helpers/fetch-from-gsm-real.sh"

echo "Testing GSM helper: $GSM_HELPER"
echo "================================="

# Test 1: Missing credential name argument
echo "Test 1: Missing credential name argument..."
if ! bash "$GSM_HELPER" 2>&1 | grep -q "Usage\|credential_name\|required"; then
  if bash "$GSM_HELPER" 2>/dev/null; then
    echo "FAIL: Expected non-zero exit"
    exit 1
  fi
fi
echo "✓ PASS: Missing arg handled correctly"

# Test 2: Missing GCP_PROJECT_ID environment variable
echo "Test 2: Missing GCP_PROJECT_ID environment variable..."
unset GCP_PROJECT_ID 2>/dev/null || true
if bash "$GSM_HELPER" test-credential 2>&1 | grep -q "GCP_PROJECT_ID\|required\|not set"; then
  echo "✓ PASS: Missing env var handled correctly"
elif ! bash "$GSM_HELPER" test-credential 2>/dev/null; then
  echo "✓ PASS: Missing env var exit code correct"
else
  echo "FAIL: Expected error handling for missing GCP_PROJECT_ID"
  exit 1
fi

# Test 3: Syntax check
echo "Test 3: Syntax check..."
if bash -n "$GSM_HELPER" 2>&1; then
  echo "✓ PASS: No syntax errors"
else
  echo "FAIL: Syntax error detected"
  exit 1
fi

echo ""
echo "All GSM helper tests passed! ✓"
