"use strict";

const jobStore = require('./jobStore');
const tr = require('./terraform_runner');
const crypto = require('crypto');
const metricsServer = require('./lib/metricsServer');
const metrics = require('./lib/metrics');

const POLL_MS = Number(process.env.WORKER_POLL_MS || '5000');
const METRICS_PORT = Number(process.env.METRICS_PORT || '9090');
const ENABLE_METRICS = process.env.ENABLE_METRICS !== 'false';

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
  metrics.updateActiveJobs(1);
  
  const tfFiles = job.payload && job.payload.tfFiles ? job.payload.tfFiles : null;
  const planHash = shaForTfFiles(tfFiles);
  if (planHash) {
    const existing = jobStore.getByPlanHash(planHash);
    if (existing && existing.request_id !== job.request_id) {
      job.status = 'duplicate';
      job.note = `duplicate_of:${existing.request_id}`;
      const storeStartTime = Date.now();
      jobStore.set(job);
      metrics.recordJobStoreWrite(Date.now() - storeStartTime);
      metrics.recordJobCompletion('duplicated', Date.now() - startTime);
      metrics.updateActiveJobs(0);
      return;
    }
  }

  job.status = 'running';
  job.started_at = new Date().toISOString();
  const storeStartTime = Date.now();
  jobStore.set(job);
  metrics.recordJobStoreWrite(Date.now() - storeStartTime);

  const tfStartTime = Date.now();
  const res = await tr.applyPlan(job).catch((e) => ({ status: 'error', reason: 'exception', error: String(e) }));
  metrics.recordTerraformApply(Date.now() - tfStartTime, res && res.status === 'applied');

  if (res && res.status === 'applied') {
    job.status = 'provisioned';
    job.result = res;
    if (planHash) jobStore.setPlanHash(planHash, job.request_id);
    metrics.recordJobCompletion('succeeded', Date.now() - startTime);
  } else {
    job.status = 'failed';
    job.result = res;
    metrics.recordJobCompletion('failed', Date.now() - startTime);
  }
  job.completed_at = new Date().toISOString();
  const storeStartTime2 = Date.now();
  jobStore.set(job);
  metrics.recordJobStoreWrite(Date.now() - storeStartTime2);
  
  metrics.updateActiveJobs(0);
}

async function loop() {
  try {
    const jobs = jobStore.list();
    metrics.updateQueueDepth(jobs.filter(j => j && (j.status === 'queued' || j.status === 'retry')).length);
    metrics.setJobStoreOperational(true);
    
    for (const j of jobs) {
      if (!j || !j.request_id) continue;
      if (j.status === 'queued' || j.status === 'retry') {
        // process asynchronously but wait to keep serial for now
        // eslint-disable-next-line no-await-in-loop
        await processJob(j);
      }
    }
  } catch (e) {
    console.error('[worker] Loop error:', e);
    metrics.setJobStoreOperational(false);
    // swallow and continue
  } finally {
    setTimeout(loop, POLL_MS);
  }
}

// Start metrics server if enabled
if (ENABLE_METRICS) {
  metricsServer.startMetricsServer(METRICS_PORT).catch(err => {
    console.error('[worker] Failed to start metrics server:', err);
  });
}

console.log('provisioner-worker: starting worker loop', { 
  poll_ms: POLL_MS, 
  use_cli: process.env.USE_TERRAFORM_CLI,
  metrics_enabled: ENABLE_METRICS,
  metrics_port: METRICS_PORT,
});
loop();
