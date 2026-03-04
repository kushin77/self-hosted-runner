#!/usr/bin/env node
const REDIS_URL = process.env.REDIS_URL || '';
const QUEUE_KEY = process.env.PROVISION_QUEUE_KEY || 'provision:queue';

async function runInMemoryWorker() {
  console.log('Starting in-memory provisioner worker (no REDIS_URL provided).');
  console.log('This is a scaffold—implement dequeue logic with Redis/SQS for production.');
  // Keep process alive
  setInterval(() => {}, 1000 * 60);
}

async function runRedisWorker() {
  console.log('Starting Redis-backed provisioner worker, connecting to', REDIS_URL);
  let redis;
  try {
    redis = require('redis');
  } catch (e) {
    console.error('redis package missing. Run `npm install` in services/provisioner-worker.');
    process.exit(1);
  }
  const client = redis.createClient({ url: REDIS_URL });
  client.on('error', (err) => console.error('Redis client error', err));
  await client.connect();
  console.log('Connected to Redis. Blocking on', QUEUE_KEY);
  while (true) {
    try {
      // brPop returns [key, element] when a value is popped
      const res = await client.brPop(QUEUE_KEY, 0);
      const element = Array.isArray(res) ? (res[1] || res.element) : (res.element || '');
      const payload = JSON.parse(element || '{}');
      console.log('Dequeued job:', payload);
      // TODO: call Terraform/cloud APIs here and update job status.
    } catch (e) {
      console.error('Worker error', String(e));
      await new Promise(r => setTimeout(r, 1000));
    }
  }
}

(async () => {
  if (REDIS_URL) return runRedisWorker();
  return runInMemoryWorker();
})();
