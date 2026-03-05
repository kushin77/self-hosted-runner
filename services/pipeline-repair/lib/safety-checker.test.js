/**
 * Safety Checker - Test Harness
 * Validates the AI Agent Safety Framework implementation
 */
const SafetyChecker = require('./safety-checker');
const ApprovalEngine = require('./approval-engine');

// Initialize safety checker
const safetyChecker = new SafetyChecker({
  maxCostIncreasePercent: 10,
  maxScalingPercent: 20,
  maxMemoryIncreaseMB: 512,
});

const approvalEngine = new ApprovalEngine({ threshold: 0.7 });

/**
 * Test: Green (auto-executable) action
 */
async function testGreenAction() {
  console.log('\n📊 Testing GREEN action (cache invalidation - auto-executable)...');
  const action = {
    id: 'act-001',
    type: 'cache_invalidation',
    scope: 'pipeline-repair-service',
    description: 'Clear in-memory repair cache to free up memory',
  };

  const result = await safetyChecker.checkSafety(action);
  console.log('Result:', JSON.stringify(result, null, 2));
  
  if (result.category === 'GREEN' && result.safe && result.violations.length === 0) {
    console.log('✅ GREEN action test PASSED');
    return true;
  } else {
    console.log('❌ GREEN action test FAILED');
    return false;
  }
}

/**
 * Test: Yellow (requires approval) action within bounds
 */
async function testYellowActionWithinBounds() {
  console.log('\n📊 Testing YELLOW action (scale up within bounds - requires approval)...');
  const action = {
    id: 'act-002',
    type: 'scale_up',
    scope: 'staging-runner-pool',
    currentCount: 5,
    targetCount: 6, // +20% within limit
    currentInstances: 5,
    maxInstances: 10,
    estimatedCostDelta: 5, // max 10% allowed
  };

  const result = await safetyChecker.checkSafety(action, {
    baseline: { currentMonthlyCost: 100 }
  });
  console.log('Result:', JSON.stringify(result, null, 2));
  
  if (result.category === 'YELLOW' && result.recommendation === 'REQUIRES_APPROVAL') {
    console.log('✅ YELLOW action test PASSED');
    return true;
  } else {
    console.log('❌ YELLOW action test FAILED');
    return false;
  }
}

/**
 * Test: Yellow action exceeds bounds (should be BLOCKED_FOR_REVIEW)
 */
async function testYellowActionExceedsBounds() {
  console.log('\n📊 Testing YELLOW action exceeding bounds (should block)...');
  const action = {
    id: 'act-003',
    type: 'scale_up',
    scope: 'staging-runner-pool',
    currentCount: 5,
    targetCount: 20, // +300%, exceeds 20% limit
    maxInstances: 20,
    estimatedCostDelta: 50, // exceeds 10% of $100 baseline
  };

  const result = await safetyChecker.checkSafety(action, {
    baseline: { currentMonthlyCost: 100 }
  });
  console.log('Result:', JSON.stringify(result, null, 2));
  
  if (result.category === 'YELLOW' && result.recommendation === 'BLOCKED_FOR_REVIEW' && result.violations.length > 0) {
    console.log('✅ YELLOW bounds test PASSED');
    return true;
  } else {
    console.log('❌ YELLOW bounds test FAILED');
    return false;
  }
}

/**
 * Test: Red (forbidden) action
 */
async function testRedAction() {
  console.log('\n📊 Testing RED action (delete data - forbidden)...');
  const action = {
    id: 'act-004',
    type: 'delete_data',
    scope: 'audit_logs',
    description: 'Permanently delete audit logs',
  };

  const result = await safetyChecker.checkSafety(action);
  console.log('Result:', JSON.stringify(result, null, 2));
  
  if (result.category === 'RED' && result.safe === false && result.recommendation === 'FORBIDDEN - this action cannot be executed autonomously') {
    console.log('✅ RED action test PASSED');
    return true;
  } else {
    console.log('❌ RED action test FAILED');
    return false;
  }
}

/**
 * Test: Reversibility check
 */
async function testReversibility() {
  console.log('\n📊 Testing Reversibility checks...');
  
  const reversibleAction = {
    id: 'act-005',
    type: 'increase_timeout',
    scope: 'single-job',
    newTimeoutSeconds: 120,
    currentTimeoutSeconds: 60,
  };

  const nonReversibleAction = {
    id: 'act-006',
    type: 'delete_logs',
    scope: 'old-logs',
    description: 'Permanently delete old logs from S3',
  };

  const rev1 = safetyChecker.isReversible(reversibleAction);
  const rev2 = safetyChecker.isReversible(nonReversibleAction);

  console.log('Reversible action:', rev1);
  console.log('Non-reversible action:', rev2);

  if (rev1.reversible === true && rev2.reversible === false) {
    console.log('✅ Reversibility test PASSED');
    return true;
  } else {
    console.log('❌ Reversibility test FAILED');
    return false;
  }
}

/**
 * Test: Scope validation
 */
async function testScopeValidation() {
  console.log('\n📊 Testing Scope validation...');
  
  const boundedScope = {
    id: 'act-007',
    type: 'scale_up',
    scope: 'runner-pool-us-east-1',
    maxInstances: 10,
    currentInstances: 5,
    targetCount: 6,
  };

  const unboundedScope = {
    id: 'act-008',
    type: 'scale_up',
    scope: 'all',
    maxInstances: Infinity,
  };

  const scope1 = safetyChecker.validateScope(boundedScope);
  const scope2 = safetyChecker.validateScope(unboundedScope);

  console.log('Bounded scope:', scope1);
  console.log('Unbounded scope:', scope2);

  if (scope1.bounded === true && scope2.bounded === false) {
    console.log('✅ Scope validation test PASSED');
    return true;
  } else {
    console.log('❌ Scope validation test FAILED');
    return false;
  }
}

/**
 * Test: Audit trail
 */
async function testAuditTrail() {
  console.log('\n📊 Testing Audit trail...');
  
  // Run a few actions to generate audit entries
  await safetyChecker.checkSafety({ type: 'cache_invalidation', scope: 'service-1' });
  await safetyChecker.checkSafety({ type: 'delete_data', scope: 'logs' });
  
  const allLogs = safetyChecker.getAuditLog();
  const redLogs = safetyChecker.getAuditLog({ category: 'RED' });
  const metrics = safetyChecker.getMetrics();

  console.log('Total audit logs:', allLogs.length);
  console.log('RED category logs:', redLogs.length);
  console.log('Safety metrics:', metrics);

  if (allLogs.length > 0 && metrics.total > 0) {
    console.log('✅ Audit trail test PASSED');
    return true;
  } else {
    console.log('❌ Audit trail test FAILED');
    return false;
  }
}

/**
 * Run all tests
 */
async function runAllTests() {
  console.log('='.repeat(70));
  console.log('AI Agent Safety Checker - Test Harness');
  console.log('='.repeat(70));

  const tests = [
    { name: 'Green Action', fn: testGreenAction },
    { name: 'Yellow Action (Within Bounds)', fn: testYellowActionWithinBounds },
    { name: 'Yellow Action (Exceeds Bounds)', fn: testYellowActionExceedsBounds },
    { name: 'Red Action', fn: testRedAction },
    { name: 'Reversibility', fn: testReversibility },
    { name: 'Scope Validation', fn: testScopeValidation },
    { name: 'Audit Trail', fn: testAuditTrail },
  ];

  const results = [];
  for (const test of tests) {
    try {
      const passed = await test.fn();
      results.push({ name: test.name, passed });
    } catch (err) {
      console.error(`❌ Test ${test.name} threw error:`, err.message);
      results.push({ name: test.name, passed: false, error: err.message });
    }
  }

  console.log('\n' + '='.repeat(70));
  console.log('Test Summary');
  console.log('='.repeat(70));
  results.forEach(r => {
    const status = r.passed ? '✅' : '❌';
    console.log(`${status} ${r.name}`);
    if (r.error) console.log(`   Error: ${r.error}`);
  });

  const passCount = results.filter(r => r.passed).length;
  console.log(`\nPassed: ${passCount}/${results.length}`);
  console.log('='.repeat(70));

  return passCount === results.length;
}

// Run tests if this is the main module
if (require.main === module) {
  runAllTests().then(allPassed => {
    process.exit(allPassed ? 0 : 1);
  }).catch(err => {
    console.error('Fatal error:', err);
    process.exit(1);
  });
}

module.exports = {
  runAllTests,
  safetyChecker,
  approvalEngine,
};
