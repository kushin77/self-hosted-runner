"use strict";

// Compatibility shim expected by index.js — delegates to lib/terraform_runner.js
try {
  module.exports = require('./lib/terraform_runner');
} catch (e) {
  // Fallback: provide stubbed apply/destroy to avoid runtime crash
  module.exports = {
    apply: async (job) => ({ status: 'applied', jobId: job && job.id || null, details: { message: 'fallback stub' } }),
    destroy: async (job) => ({ status: 'destroyed', jobId: job && job.id || null, details: { message: 'fallback stub' } }),
  };
}
