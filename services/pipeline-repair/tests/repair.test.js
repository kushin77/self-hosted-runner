const assert = require('assert');
const RetryStrategy = require('../strategies/retry');

(async () => {
  console.log('Running RetryStrategy unit tests...');

  // Create deterministic strategy (no jitter)
  const strat = new RetryStrategy({ maxAttempts: 3, baseDelayMs: 100, maxDelayMs: 1000, jitter: false });

  // Test assess() detects transient error
  const assessScore = strat.assess({ errorMessage: 'timeout while connecting to artifact store' });
  assert.strictEqual(typeof assessScore, 'number');
  assert.ok(assessScore > 0, 'assess should return confidence > 0 for transient errors');

  // Test execute() for first attempt returns RETRY with expected delay
  const exec1 = await strat.execute({ attemptNumber: 1 });
  assert.strictEqual(exec1.action, 'RETRY');
  assert.strictEqual(exec1.parameters.attempt, 2);
  assert.strictEqual(exec1.parameters.maxAttempts, 3);
  // baseDelayMs * 2^(attempt-1) => 100 * 1 = 100
  assert.strictEqual(exec1.parameters.delayMs, 100);

  // Test execute() escalates when attempts reached
  const execEsc = await strat.execute({ attemptNumber: 3 });
  assert.strictEqual(execEsc.action, 'ESCALATE');
  assert.strictEqual(execEsc.parameters.maxAttempts, 3);

  console.log('All RetryStrategy tests passed.');
})();
