#!/usr/bin/env node
const RepairService = require('../lib/repair-service');
const logger = require('winston');

async function runScenario(event) {
  const svc = new RepairService();
  const res = await svc.analyze(event);
  console.log('\n=== Scenario Result ===');
  console.log(JSON.stringify(res, null, 2));
}

(async ()=>{
  console.log('Running GREEN scenario (timeout -> retry)');
  await runScenario({ id: 'evt-green', errorMessage: 'Error: Connection timeout after 30s', scope: 'service-api', attemptNumber: 1, baseline: { currentMonthlyCost: 100 } });

  console.log('\nRunning YELLOW scenario (timeout with value -> increase timeout)');
  await runScenario({ id: 'evt-yellow', errorMessage: 'Operation timed out after 15 seconds', scope: 'runner-pool', currentCount: 5, targetCount: 6, attemptNumber: 2, baseline: { currentMonthlyCost: 100 } });

  console.log('\nRunning RED scenario (delete data attempt)');
  await runScenario({ id: 'evt-red', errorMessage: 'Permanently delete audit logs', scope: 'audit_logs', actionType: 'delete_data', baseline: { currentMonthlyCost: 100 } });
})();
