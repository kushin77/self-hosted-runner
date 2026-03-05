"use strict";

const useCli = (process.env.USE_TERRAFORM_CLI || '0') === '1';

if (useCli) {
  // prefer the CLI runner
  module.exports = require('./lib/terraform_runner_cli');
} else {
  // stub runner (no-op), keeps the API stable for tests and simulate mode
  async function applyPlan(job, opts = {}) {
    return { status: 'applied', jobId: job.request_id || job.id || null, message: 'stub-applied' };
  }
  async function destroyPlan(job, opts = {}) {
    return { status: 'destroyed', jobId: job.request_id || job.id || null, message: 'stub-destroyed' };
  }
  module.exports = { applyPlan, destroyPlan };
}
