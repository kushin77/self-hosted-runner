#!/usr/bin/env bash
set -euo pipefail

FIXTURE=scripts/test/milestone_fixture.json
PY=scripts/utilities/milestone_heuristic.py

echo "Running local milestone heuristic test against fixture: $FIXTURE"
python3 "$PY" "$FIXTURE" > /tmp/milestone_test_output.json
cat /tmp/milestone_test_output.json

COUNT=$(jq 'length' /tmp/milestone_test_output.json)
echo "Assignments: $COUNT"
if [ "$COUNT" -lt 1 ]; then
  echo "Test failed: expected at least 1 assignment" >&2
  exit 1
fi
echo "Test passed"
