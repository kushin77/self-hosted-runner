#!/usr/bin/env node
const provisioner = require('../provisioner');

(async () => {
  if (!process.env.REDIS_URL) {
    console.error('Set REDIS_URL to enqueue to Redis.');
    process.exit(2);
  }
  console.log('Enqueueing job to Redis queue via provisioner API...');
  const res = await provisioner.enqueue({ runner_meta: { type: 'redis-demo' } });
  console.log('Enqueue result:', res);
  process.exit(0);
})();
