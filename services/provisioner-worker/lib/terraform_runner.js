"use strict";

// Terraform runner stub for provisioner-worker
// Replace this with a real Terraform workspace invocation (child_process
// calling `terraform init/plan/apply`) or a Terraform SDK wrapper.

const { spawn } = require('child_process');

async function applyPlan(job, opts = {}) {
  // job: { id, type, payload }
  // opts: { dryRun, timeout }
  // This stub simulates applying a plan and returns a consistent result.
  return new Promise((resolve) => {
    const result = {
      status: 'applied',
      jobId: job.id,
      timestamp: new Date().toISOString(),
      details: {
        message: 'terraform_runner stub applied (no-op)',
      },
    };
    setTimeout(() => resolve(result), 300);
  });
}

async function destroyPlan(job, opts = {}) {
  return new Promise((resolve) => {
    const result = {
      status: 'destroyed',
      jobId: job.id,
      timestamp: new Date().toISOString(),
      details: {
        message: 'terraform_runner stub destroyed (no-op)',
      },
    };
    setTimeout(() => resolve(result), 300);
  });
}

module.exports = {
  applyPlan,
  destroyPlan,
};
