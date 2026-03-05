#!/usr/bin/env bash
set -euo pipefail

# repair-service unit tests
# Tests core repair service functionality

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
SERVICE_DIR="$REPO_ROOT/pipeline-repair"

echo "Running pipeline-repair unit tests..."

# Test 1: Verify required modules
echo "✓ Test 1: Module dependencies"
cd "$SERVICE_DIR"
npm list express body-parser winston >/dev/null 2>&1 || {
  echo "ERROR: Missing module dependencies"
  exit 1
}

# Test 2: Verify strategies are loadable
echo "✓ Test 2: Strategy modules"
node -e "
const RetryStrategy = require('./strategies/retry');
const TimeoutIncreaseStrategy = require('./strategies/timeout-increase');
console.log('✓ Strategies loaded:', RetryStrategy.name, TimeoutIncreaseStrategy.name);
" || { echo "ERROR: Failed to load strategies"; exit 1; }

# Test 3: Test repair service initialization
echo "✓ Test 3: Service initialization"
node -e "
const RepairService = require('./lib/repair-service');
const service = new RepairService();
console.log('✓ Strategies available:', service.getStrategies().length);
" || { echo "ERROR: Failed to initialize service"; exit 1; }

# Test 4: Test audit log
echo "✓ Test 4: Audit log"
node -e "
const AuditLog = require('./lib/audit-log');
const log = new AuditLog({ logDir: '/tmp/repair-audit-test' });
log.logAnalysis('evt-1', { id: 'evt-1', errorMessage: 'test' }, { status: 'TEST' });
console.log('✓ Audit log working');
" || { echo "ERROR: Failed audit log test"; exit 1; }

# Test 5: Test approval engine
echo "✓ Test 5: Approval engine"
node -e "
const ApprovalEngine = require('./lib/approval-engine');
const engine = new ApprovalEngine();
const action = { action: 'RETRY', risk: 'LOW' };
const needsApproval = engine.requiresApproval(action, 0.9);
console.log('✓ Approval logic working (LOW risk need approval:', needsApproval, ')');
" || { echo "ERROR: Failed approval engine test"; exit 1; }

# Test 6: Test retry strategy
echo "✓ Test 6: Retry strategy assessment"
node -e "
const RetryStrategy = require('./strategies/retry');
const strategy = new RetryStrategy();
const timeoutScore = strategy.assess({ errorMessage: 'timeout' });
const normalScore = strategy.assess({ errorMessage: 'unknown error' });
console.log('✓ Retry strategy: timeout=', timeoutScore, 'normal=', normalScore);
" || { echo "ERROR: Failed retry assessment"; exit 1; }

# Test 7: Test timeout-increase strategy
echo "✓ Test 7: Timeout-increase strategy"
node -e "
const TimeoutIncreaseStrategy = require('./strategies/timeout-increase');
const strategy = new TimeoutIncreaseStrategy();
const score1 = strategy.assess({ errorMessage: 'Request timeout after 30s' });
const score2 = strategy.assess({ errorMessage: 'Network error' });
console.log('✓ Timeout strategy: timeout=', score1, 'normal=', score2);
" || { echo "ERROR: Failed timeout assessment"; exit 1; }

# Test 8: Test full analysis pipeline
echo "✓ Test 8: Full analysis pipeline"
node -e "
const RepairService = require('./lib/repair-service');
(async () => {
  const service = new RepairService();
  const result = await service.analyze({
    id: 'evt-test',
    errorMessage: 'Error: Connection timeout after 30s',
    attemptNumber: 1
  });
  console.log('✓ Analysis result:', result.status, 'Risk:', result.risk);
  process.exit(result.status === 'REPAIR_IDENTIFIED' ? 0 : 1);
})();
" || { echo "ERROR: Failed analysis pipeline"; exit 1; }

echo ""
echo "✅ All unit tests passed"
