// Simple provisioner interface used by tests and prototype scaffolds.
// By default operates in-process (memory). If `REDIS_URL` is set, enqueue will
// push jobs to the Redis list `PROVISION_QUEUE_KEY` for an external worker to
// consume.
const REDIS_URL = process.env.REDIS_URL || '';
const QUEUE_KEY = process.env.PROVISION_QUEUE_KEY || 'provision:queue';

let redisClient = null;
if (REDIS_URL) {
  try {
    const redis = require('redis');
    redisClient = redis.createClient({ url: REDIS_URL });
    redisClient.connect().catch((e) => {
      console.error('provisioner: failed to connect to redis', e);
      redisClient = null;
    });
  } catch (e) {
    console.warn('provisioner: redis package not installed; falling back to memory queue');
    redisClient = null;
  }
}

const queue = [];
let processing = false;

function delay(ms) { return new Promise(resolve => setTimeout(resolve, ms)); }

async function worker() {
  if (processing) return;
  processing = true;
  while (queue.length) {
    const { job, resolve } = queue.shift();
    try {
      await delay(250);
      const runnerId = `runner-${Math.random().toString(36).slice(2,10)}`;
      await delay(50);
      resolve({ status: 'provisioned', runner_id: runnerId, meta: job.runner_meta || {} });
    } catch (e) {
      resolve({ status: 'error', error: String(e) });
    }
  }
  processing = false;
}

async function enqueue(job) {
  if (redisClient) {
    try {
      const payload = JSON.stringify(job);
      await redisClient.lPush(QUEUE_KEY, payload);
      return { status: 'queued', queue: QUEUE_KEY };
    } catch (e) {
      // fallthrough to in-memory if redis push fails
      console.error('provisioner: redis push failed, falling back to memory', String(e));
    }
  }
  return new Promise((resolve) => {
    queue.push({ job, resolve });
    worker().catch(() => {});
  });
}

module.exports = { enqueue };
