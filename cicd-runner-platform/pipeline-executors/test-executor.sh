#!/usr/bin/env bash
##
## Test Executor
## Runs test jobs (unit, integration, contract) with full isolation.
##
set -euo pipefail

JOB_ID="${1:-unknown}"
TEST_SUITE="${2:-all}"

SANDBOX_NAME="test-${JOB_ID}-$(date +%s)"
SANDBOX_IMAGE="$(cat /etc/hostname)-runner:latest"

echo "Test Executor: ${JOB_ID}"
echo "Suite: ${TEST_SUITE}"

cleanup() {
  echo "Cleaning test environment..."
  docker rm -f "${SANDBOX_NAME}" 2>/dev/null || true
  docker network rm "test-net-${JOB_ID}" 2>/dev/null || true
}

trap cleanup EXIT

# Create isolated test network
docker network create "test-net-${JOB_ID}" --driver bridge || true

# Run tests in isolated container
echo "Running tests in sandbox..."
docker run \
  --rm \
  --name="${SANDBOX_NAME}" \
  --network="test-net-${JOB_ID}" \
  --user=tester:tester \
  --tmpfs /tmp:noexec,nosuid,nodev \
  --cap-drop=ALL \
  --cap-add=NET_BIND_SERVICE \
  --security-opt="no-new-privileges:true" \
  -e "TEST_SUITE=${TEST_SUITE}" \
  -e "JOB_ID=${JOB_ID}" \
  -e "CI=true" \
  -v "$(pwd):/workspace:ro" \
  -v "/tmp/${JOB_ID}:/test-output:rw" \
  "${SANDBOX_IMAGE}" \
  bash -c "
    cd /workspace
    case '${TEST_SUITE}' in
      unit)
        npm test -- --coverage --outputFile=/test-output/coverage.json
        ;;
      integration)
        npm run test:integration --outputDir=/test-output
        ;;
      contract)
        npm run test:contract --outputDir=/test-output
        ;;
      all|*)
        npm test -- --coverage --outputFile=/test-output/coverage.json && \
        npm run test:integration --outputDir=/test-output && \
        npm run test:contract --outputDir=/test-output
        ;;
    esac
  "

TEST_RESULT=$?

# Collect test results
if [ -d "/tmp/${JOB_ID}" ]; then
  echo "Test results:"
  ls -lh "/tmp/${JOB_ID}/"
fi

if [ ${TEST_RESULT} -eq 0 ]; then
  echo "✓ Tests passed"
else
  echo "✗ Tests failed"
  exit 1
fi
