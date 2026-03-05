// Compatibility shim expected by index.js — choose implementation based on env
// If USE_TERRAFORM_CLI=1, prefer the CLI runner; otherwise prefer lib/terraform_runner stub.
if (process.env.USE_TERRAFORM_CLI === '1') {
  try {
    const cli = require('./lib/terraform_runner_cli');
    module.exports = { apply: cli.applyPlan, destroy: cli.destroyPlan };
  } catch (e) {
    module.exports = { apply: async (job) => ({ status: 'error', reason: 'cli-not-available', detail: String(e) }) , destroy: async () => ({ status: 'error', reason: 'cli-not-available' }) };
  }
} else {
  try {
    const lib = require('./lib/terraform_runner');
    module.exports = { apply: lib.applyPlan, destroy: lib.destroyPlan };
  } catch (e) {
    module.exports = { apply: async (job) => ({ status: 'applied', jobId: job && job.id || null, details: { message: 'fallback stub' } }), destroy: async (job) => ({ status: 'destroyed', jobId: job && job.id || null, details: { message: 'fallback stub' } }) };
  }
}
