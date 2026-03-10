#!/usr/bin/env bash
set -euo pipefail

echo "Running test_audit_store"
python3 scripts/cloudrun/tests/test_audit_store.py

echo "Running test_persistent_jobs"
python3 scripts/cloudrun/tests/test_persistent_jobs.py

echo "ALL TESTS PASSED"
