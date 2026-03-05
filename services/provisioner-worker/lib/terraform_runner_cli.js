"use strict";

const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

function runCommand(cmd, args, opts = {}) {
  return new Promise((resolve, reject) => {
    const p = spawn(cmd, args, Object.assign({ stdio: ['ignore', 'pipe', 'pipe'] }, opts));
    let stdout = '';
    let stderr = '';
    p.stdout.on('data', (d) => (stdout += d.toString()));
    p.stderr.on('data', (d) => (stderr += d.toString()));
    p.on('error', (err) => reject(err));
    p.on('close', (code) => resolve({ code, stdout, stderr }));
  });
}

function terraformExists() {
  try {
    const which = spawn('which', ['terraform']);
    // Synchronous check via exit code isn't trivial here; attempt a quick spawn
    return new Promise((resolve) => {
      which.on('close', (code) => resolve(code === 0));
      which.on('error', () => resolve(false));
    });
  } catch (e) {
    return Promise.resolve(false);
  }
}

async function applyPlan(job, opts = {}) {
  const base = process.cwd();
  const workdir = path.join(base, 'services', 'provisioner-worker', 'workspaces', String(job.request_id || job.id || 'anon'));
  fs.mkdirSync(workdir, { recursive: true });

  // write TF files if provided
  if (job.payload && job.payload.tfFiles) {
    for (const [fname, content] of Object.entries(job.payload.tfFiles)) {
      fs.writeFileSync(path.join(workdir, fname), content, 'utf8');
    }
  } else if (!fs.existsSync(path.join(workdir, 'main.tf'))) {
    fs.writeFileSync(path.join(workdir, 'main.tf'), 'resource "null_resource" "noop" {}\n', 'utf8');
  }

  const hasTf = await terraformExists();
  if (!hasTf) {
    return { status: 'error', reason: 'terraform-not-found', message: 'terraform binary not found on PATH; install terraform to enable CLI runner' };
  }

  const env = Object.assign({}, process.env);

  const init = await runCommand('terraform', ['init', '-input=false', '-no-color'], { cwd: workdir, env });
  if (init.code !== 0) {
    return { status: 'error', phase: 'init', rc: init.code, stdout: init.stdout, stderr: init.stderr };
  }

  const planOut = path.join(workdir, 'plan.tfplan');
  const plan = await runCommand('terraform', ['plan', '-input=false', '-no-color', '-out', planOut], { cwd: workdir, env });
  if (plan.code !== 0) {
    return { status: 'error', phase: 'plan', rc: plan.code, stdout: plan.stdout, stderr: plan.stderr };
  }

  const apply = await runCommand('terraform', ['apply', '-input=false', '-no-color', '-auto-approve', planOut], { cwd: workdir, env });
  if (apply.code !== 0) {
    return { status: 'error', phase: 'apply', rc: apply.code, stdout: apply.stdout, stderr: apply.stderr };
  }

  return { status: 'applied', jobId: job.request_id || job.id || null, stdout: apply.stdout };
}

async function destroyPlan(job, opts = {}) {
  const base = process.cwd();
  const workdir = path.join(base, 'services', 'provisioner-worker', 'workspaces', String(job.request_id || job.id || 'anon'));
  if (!fs.existsSync(workdir)) return { status: 'not_found', jobId: job.request_id || job.id || null };
  const hasTf = await terraformExists();
  if (!hasTf) return { status: 'error', reason: 'terraform-not-found' };
  const env = Object.assign({}, process.env);
  const destroy = await runCommand('terraform', ['destroy', '-auto-approve', '-input=false', '-no-color'], { cwd: workdir, env });
  if (destroy.code !== 0) return { status: 'error', phase: 'destroy', rc: destroy.code, stdout: destroy.stdout, stderr: destroy.stderr };
  return { status: 'destroyed', jobId: job.request_id || job.id || null, stdout: destroy.stdout };
}

module.exports = { applyPlan, destroyPlan };
