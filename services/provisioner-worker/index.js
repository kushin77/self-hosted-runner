#!/usr/bin/env node
const REDIS_URL = process.env.REDIS_URL || '';
const QUEUE_KEY = process.env.PROVISION_QUEUE_KEY || 'provision:queue';
const jobStore = require('./jobStore');
const terraform = require('./terraform_runner');
const promClient = require('prom-client');
const http = require('http');
const crypto = require('crypto');

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

// Simple structured logger
function log(level, msg, meta = {}) {
  const out = Object.assign({ ts: new Date().toISOString(), level, msg }, meta);
  console.log(JSON.stringify(out));
}

// Prometheus metrics
const collectDefault = promClient.collectDefaultMetrics;
collectDefault({ timeout: 5000 });
const jobProcessed = new promClient.Counter({ name: 'provisioner_jobs_processed_total', help: 'Total processed jobs' });
const jobFailed = new promClient.Counter({ name: 'provisioner_jobs_failed_total', help: 'Total failed jobs' });
const jobAttempts = new promClient.Counter({ name: 'provisioner_job_attempts_total', help: 'Total job attempts' });

// Expose /metrics
const METRICS_PORT = parseInt(process.env.METRICS_PORT || '9091', 10);
http.createServer(async (req, res) => {
  if (req.url === '/metrics') {
    res.setHeader('Content-Type', promClient.register.contentType);
    res.end(await promClient.register.metrics());
    return;
  }
  res.writeHead(404); res.end();
}).listen(METRICS_PORT);
log('info', 'metrics-server-started', { port: METRICS_PORT });

const preferCli = process.env.USE_TERRAFORM_CLI === '1';
if (preferCli) log('info', 'terraform-runner-mode', { mode: 'cli' });
else log('info', 'terraform-runner-mode', { mode: 'lib' });

async function handleJob(job) {
  const jobId = job.request_id || `${Date.now()}-${Math.random().toString(36).slice(2,6)}`;

  // compute a planHash when TF files are supplied to enable idempotency
  let planHash = null;
  try {
    if (job && job.payload && job.payload.tfFiles) {
      const h = crypto.createHash('sha256');
      h.update(JSON.stringify(job.payload.tfFiles));
      planHash = h.digest('hex');
      if (typeof jobStore.getByPlanHash === 'function') {
        const byHash = jobStore.getByPlanHash(planHash);
        if (byHash && byHash.status === 'provisioned') {
          log('info', 'job-already-provisioned-by-planhash', { jobId: byHash.request_id || byHash.jobId, planHash });
          return byHash;
        }
      }
    }
  } catch (e) {
    // non-fatal; continue to normal flow
    log('warn', 'planhash-failed', { error: String(e) });
  }

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
      jobStore.set(jobId, { request_id: jobId, status: 'in-progress', attempts: attempt, updated_at: Date.now() });
      jobAttempts.inc();
      log('info', 'job-attempt', { jobId, attempt });
      // If using CLI mode and tfFiles present, prefer the CLI runner (shim will choose correctly too)
      if (preferCli && job && job.payload && job.payload.tfFiles) log('info', 'using-cli-runner', { jobId });
      const res = await terraform.apply(job);
      const record = { request_id: jobId, status: 'provisioned', result: res, attempts: attempt, updated_at: Date.now() };
      if (planHash && typeof jobStore.setPlanHash === 'function') {
        record.planHash = planHash;
        jobStore.setPlanHash(planHash, jobId);
      }
      jobStore.set(jobId, record);
      jobProcessed.inc();
      log('info', 'job-provisioned', { jobId, result: res });
      return record;
    } catch (e) {
      log('error', 'provision-attempt-failed', { jobId, attempt, error: String(e) });
      jobStore.set(jobId, { request_id: jobId, status: 'error', attempts: attempt, error: String(e), updated_at: Date.now() });
      if (attempt > maxRetries) throw e;
      jobFailed.inc();
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
