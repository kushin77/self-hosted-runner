#!/usr/bin/env node
const provisioner = require('../provisioner');

(async () => {
  console.log('Enqueueing demo provision job...');
  try {
    const result = await provisioner.enqueue({ runner_meta: { type: 'demo', created_by: 'demo_enqueue' } });
    console.log('Provisioner result:', result);
    process.exit(0);
  } catch (e) {
    console.error('Error enqueueing job:', e);
    process.exit(2);
  }
})();
