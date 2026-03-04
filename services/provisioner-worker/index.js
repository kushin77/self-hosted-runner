#!/usr/bin/env node
const REDIS_URL = process.env.REDIS_URL || '';
const QUEUE_KEY = process.env.PROVISION_QUEUE_KEY || 'provision:queue';
const jobStore = require('./jobStore');
const terraform = require('./terraform_runner');

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

async function handleJob(job) {
  const jobId = job.request_id || `${Date.now()}-${Math.random().toString(36).slice(2,6)}`;
  const existing = jobStore.get(jobId);
  if (existing && existing.status === 'provisioned') {
    console.log('Job', jobId, 'already provisioned, skipping');
    return existing;
  }

  const maxRetries = parseInt(process.env.PROVISION_MAX_RETRIES || '3', 10);
  let attempt = (existing && existing.attempts) ? existing.attempts : 0;
  while (attempt <= maxRetries) {
    try {
      attempt++;
      jobStore.set(jobId, { status: 'in-progress', attempts: attempt, updated_at: Date.now() });
      console.log('Attempt', attempt, 'for job', jobId);
      const res = await terraform.apply(job);
      const record = { status: 'provisioned', result: res, attempts: attempt, updated_at: Date.now() };
      jobStore.set(jobId, record);
      console.log('Job', jobId, 'provisioned:', res);
      return record;
    } catch (e) {
      console.error('Provision attempt failed for job', jobId, String(e));
      jobStore.set(jobId, { status: 'error', attempts: attempt, error: String(e), updated_at: Date.now() });
      if (attempt > maxRetries) throw e;
      const backoff = Math.min(1000 * Math.pow(2, attempt), 30000);
      console.log('Retrying after', backoff, 'ms');
      await sleep(backoff);
    }
  }
}

async function runInMemoryWorker() {
  console.log('Starting in-memory provisioner worker (no REDIS_URL provided).');
  console.log('Listening for enqueue() calls to process jobs in-process.');
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
      const res = await client.brPop(QUEUE_KEY, 0);
      const element = Array.isArray(res) ? (res[1] || res.element) : (res.element || '');
      const payload = JSON.parse(element || '{}');
      console.log('Dequeued job:', payload);
      await handleJob(payload);
    } catch (e) {
      console.error('Worker error', String(e));
      await sleep(1000);
    }
  }
}

(async () => {
  if (REDIS_URL) return runRedisWorker();
  return runInMemoryWorker();
})();
