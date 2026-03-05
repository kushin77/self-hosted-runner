"use strict";

const jobStore = require('./jobStore');
const tr = require('./terraform_runner');
const crypto = require('crypto');
const metricsServer = require('./lib/metricsServer');
const metrics = require('./lib/metrics');
const logger = require('./lib/logger');
const otel = require('./lib/otel.cjs');

// initialize telemetry (no-op if packages missing or ENABLE_OTEL!=true)
otel.init();

const POLL_MS = Number(process.env.WORKER_POLL_MS || '5000');
const METRICS_PORT = Number(process.env.METRICS_PORT || '9090');
const ENABLE_METRICS = process.env.ENABLE_METRICS !== 'false';

// correlation id for this instance (could be overridden per-job)
const INSTANCE_ID = process.env.INSTANCE_ID || logger.genCorrelationId();
logger.info('provisioner-worker initializing',{instance_id:INSTANCE_ID});

function shaForTfFiles(tfFiles) {
  try {
    const s = JSON.stringify(tfFiles || {});
    return crypto.createHash('sha256').update(s).digest('hex');
  } catch (e) {
    return null;
  }
}

async function processJob(job) {
  const startTime = Date.now();
  let jobLog = logger.child({correlation_id: job.request_id || logger.genCorrelationId()});
  jobLog.info('processing job', {status: job.status});

  // start a tracing span if tracer is available
  const tracer = otel.getTracer();
  const span = tracer ? tracer.startSpan('processJob', { attributes: { request_id: job.request_id } }) : null;
  if (span) span.setAttribute('job.status', job.status);
  if (ENABLE_METRICS) metrics.updateActiveJobs(metrics.metrics.active_jobs + 1);
  if (span) span.addEvent('metrics.increment_active');
  const tfFiles = job.payload && job.payload.tfFiles ? job.payload.tfFiles : null;
  const planHash = shaForTfFiles(tfFiles);
  if (planHash) {
    const existing = jobStore.getByPlanHash(planHash);
    if (existing && existing.request_id !== job.request_id) {
      job.status = 'duplicate';
      job.note = `duplicate_of:${existing.request_id}`;
      const storeStart = Date.now();
      jobStore.set(job);
      if (ENABLE_METRICS) metrics.recordJobStoreWrite(Date.now() - storeStart);
      if (ENABLE_METRICS) metrics.recordJobCompletion('duplicated', Date.now() - startTime);
      if (ENABLE_METRICS) metrics.updateActiveJobs(metrics.metrics.active_jobs - 1);
      if (span) span.addEvent('metrics.decrement_active');
      jobLog.warn('job duplicate detected');
      return;
    }
  }

  job.status = 'running';
  job.started_at = new Date().toISOString();
  const storeStart = Date.now();
  jobStore.set(job);
  if (ENABLE_METRICS) metrics.recordJobStoreWrite(Date.now() - storeStart);

  const tfStart = Date.now();
  const res = await tr.applyPlan(job).catch((e) => {
    jobLog.error('terraform apply exception', {error: String(e)});
    return { status: 'error', reason: 'exception', error: String(e) };
  });
  if (ENABLE_METRICS) metrics.recordTerraformApply(Date.now() - tfStart, res && res.status === 'applied');

  if (res && res.status === 'applied') {
    job.status = 'provisioned';
    job.result = res;
    if (planHash) jobStore.setPlanHash(planHash, job.request_id);
    if (ENABLE_METRICS) metrics.recordJobCompletion('succeeded', Date.now() - startTime);
    jobLog.info('job provisioned');
  } else {
    job.status = 'failed';
    job.result = res;
    if (ENABLE_METRICS) metrics.recordJobCompletion('failed', Date.now() - startTime);
    jobLog.error('job failed', {result: res});
  }
  job.completed_at = new Date().toISOString();
  const storeStart2 = Date.now();
  jobStore.set(job);
  if (ENABLE_METRICS) metrics.recordJobStoreWrite(Date.now() - storeStart2);

  if (ENABLE_METRICS) metrics.updateActiveJobs(metrics.metrics.active_jobs - 1);
  if (span) span.addEvent('metrics.decrement_active');
  if (span) span.end();
}

async function loop() {
  try {
    const jobs = jobStore.list();
    if (ENABLE_METRICS) {
      metrics.updateQueueDepth(jobs.filter(j => j && (j.status === 'queued' || j.status === 'retry')).length);
      metrics.setJobStoreOperational(true);
    }
    for (const j of jobs) {
      if (!j || !j.request_id) continue;
      if (j.status === 'queued' || j.status === 'retry') {
        // process asynchronously but wait to keep serial for now
        // eslint-disable-next-line no-await-in-loop
        await processJob(j);
      }
    }
  } catch (e) {
    logger.error('worker loop error', {error: String(e)});
    if (ENABLE_METRICS) metrics.setJobStoreOperational(false);
    // swallow and continue
  } finally {
    setTimeout(loop, POLL_MS);
  }
}

// Start metrics server if enabled
if (ENABLE_METRICS) {
  metricsServer.startMetricsServer(METRICS_PORT).catch(err => {
    logger.error('Failed to start metrics server', {error: String(err)});
  });
}

logger.info('provisioner-worker: starting worker loop', { 
  poll_ms: POLL_MS, 
  use_cli: process.env.USE_TERRAFORM_CLI,
  metrics_enabled: ENABLE_METRICS,
  metrics_port: METRICS_PORT,
  instance_id: INSTANCE_ID,
});
loop();
