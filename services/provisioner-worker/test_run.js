"use strict";

// Test runner script: starts the provisioner-worker in-process and enqueues a test job

const path = require('path');

// Require index.js to start the worker loop and metrics server
require(path.join(__dirname, 'index.js'));

// Small delay to let worker initialize
setTimeout(async () => {
  try {
    const provisioner = require('../provisioner');
    console.log('Enqueuing test job...');
    const res = await provisioner.enqueue({ request_id: 'test-run-1', runner_meta: { os: 'linux' } });
    console.log('Enqueue returned:', res);
    // Wait to let worker process
    setTimeout(() => {
      console.log('Test run complete - check logs above for provisioning result.');
      process.exit(0);
    }, 1500);
  } catch (e) {
    console.error('Test run failed:', e);
    process.exit(2);
  }
}, 500);
