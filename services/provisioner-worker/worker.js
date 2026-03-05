"use strict";

const jobStore = require('./jobStore');
const tr = require('./terraform_runner');
const crypto = require('crypto');

const POLL_MS = Number(process.env.WORKER_POLL_MS || '5000');

function shaForTfFiles(tfFiles) {
  try {
    const s = JSON.stringify(tfFiles || {});
    return crypto.createHash('sha256').update(s).digest('hex');
  } catch (e) {
    return null;
  }
}

async function processJob(job) {
  const tfFiles = job.payload && job.payload.tfFiles ? job.payload.tfFiles : null;
  const planHash = shaForTfFiles(tfFiles);
  if (planHash) {
    const existing = jobStore.getByPlanHash(planHash);
    if (existing && existing.request_id !== job.request_id) {
      job.status = 'duplicate';
      job.note = `duplicate_of:${existing.request_id}`;
      jobStore.set(job);
      return;
    }
  }

  job.status = 'running';
  job.started_at = new Date().toISOString();
  jobStore.set(job);

  const res = await tr.applyPlan(job).catch((e) => ({ status: 'error', reason: 'exception', error: String(e) }));

  if (res && res.status === 'applied') {
    job.status = 'provisioned';
    job.result = res;
    if (planHash) jobStore.setPlanHash(planHash, job.request_id);
  } else {
    job.status = 'failed';
    job.result = res;
  }
  job.completed_at = new Date().toISOString();
  jobStore.set(job);
}

async function loop() {
  try {
    const jobs = jobStore.list();
    for (const j of jobs) {
      if (!j || !j.request_id) continue;
      if (j.status === 'queued' || j.status === 'retry') {
        // process asynchronously but wait to keep serial for now
        // eslint-disable-next-line no-await-in-loop
        await processJob(j);
      }
    }
  } catch (e) {
    // swallow and continue
  } finally {
    setTimeout(loop, POLL_MS);
  }
}

console.log('provisioner-worker: starting worker loop', { poll_ms: POLL_MS, use_cli: process.env.USE_TERRAFORM_CLI });
loop();
