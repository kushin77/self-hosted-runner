// Simple in-process provisioner worker used by local tests and prototypes.
// Exposes enqueue(job) which returns a Promise resolving to a runner id.
const queue = [];
let processing = false;

function delay(ms) { return new Promise(resolve => setTimeout(resolve, ms)); }

async function worker() {
  if (processing) return;
  processing = true;
  while (queue.length) {
    const { job, resolve } = queue.shift();
    try {
      // Simulate provisioning delay
      await delay(250);
      const runnerId = `runner-${Math.random().toString(36).slice(2,10)}`;
      // simulate a short post-provision delay
      await delay(50);
      resolve({ status: 'provisioned', runner_id: runnerId, meta: job.runner_meta || {} });
    } catch (e) {
      resolve({ status: 'error', error: String(e) });
    }
  }
  processing = false;
}

function enqueue(job) {
  return new Promise((resolve) => {
    queue.push({ job, resolve });
    worker().catch(() => {});
  });
}

module.exports = { enqueue };
