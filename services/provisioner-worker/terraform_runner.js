const { exec } = require('child_process');

const SIMULATE = process.env.SIMULATE_TERRAFORM === '1' || true;

function delay(ms) { return new Promise(res => setTimeout(res, ms)); }

async function apply(job) {
  if (SIMULATE) {
    // Simulate a provisioning run
    await delay(500);
    return { status: 'provisioned', runner_id: `runner-${Math.random().toString(36).slice(2,10)}` };
  }

  // Real invocation (optional): run external terraform command set in TERRAFORM_CMD
  const cmd = process.env.TERRAFORM_CMD || 'echo no-terraform-cmd-provided';
  return new Promise((resolve, reject) => {
    exec(cmd, { timeout: 1000 * 60 * 5 }, (err, stdout, stderr) => {
      if (err) return reject(err);
      resolve({ status: 'provisioned', output: stdout });
    });
  });
}

module.exports = { apply };
