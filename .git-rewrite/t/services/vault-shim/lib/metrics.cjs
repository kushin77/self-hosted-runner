"use strict";

// Basic Prometheus metrics for vault-shim service (Phase P3.5)

const metrics = {
  requests_total: 0,
  requests_success_total: 0,
  requests_failure_total: 0,
  request_latency_ms: [],
  active_requests: 0,
  last_request_at: null,
  start_time: new Date().toISOString(),
};

function recordRequest(status, duration_ms) {
  metrics.requests_total++;
  if (status === 'success') {
    metrics.requests_success_total++;
  } else if (status === 'failure') {
    metrics.requests_failure_total++;
  }
  metrics.last_request_at = new Date().toISOString();
  metrics.request_latency_ms.push(duration_ms);
  if (metrics.request_latency_ms.length > 1000) {
    metrics.request_latency_ms.shift();
  }
}

function incActive() {
  metrics.active_requests++;
}

function decActive() {
  if (metrics.active_requests > 0) metrics.active_requests--;
}

function percentile(arr, p) {
  if (arr.length === 0) return 0;
  const sorted = [...arr].sort((a, b) => a - b);
  const index = Math.ceil((p / 100) * sorted.length) - 1;
  return sorted[Math.max(0, index)];
}

function getPrometheusMetrics() {
  const lines = [];
  lines.push('# HELP vault_shim_requests_total Total HTTP requests');
  lines.push('# TYPE vault_shim_requests_total counter');
  lines.push(`vault_shim_requests_total ${metrics.requests_total}`);
  lines.push('# HELP vault_shim_requests_success_total Successful responses');
  lines.push('# TYPE vault_shim_requests_success_total counter');
  lines.push(`vault_shim_requests_success_total ${metrics.requests_success_total}`);
  lines.push('# HELP vault_shim_requests_failure_total Failed responses');
  lines.push('# TYPE vault_shim_requests_failure_total counter');
  lines.push(`vault_shim_requests_failure_total ${metrics.requests_failure_total}`);
  lines.push('# HELP vault_shim_active_requests In-flight requests');
  lines.push('# TYPE vault_shim_active_requests gauge');
  lines.push(`vault_shim_active_requests ${metrics.active_requests}`);
  if (metrics.request_latency_ms.length > 0) {
    lines.push('# HELP vault_shim_request_latency_ms Request latency in ms');
    lines.push('# TYPE vault_shim_request_latency_ms histogram');
    const sum = metrics.request_latency_ms.reduce((a, b) => a + b, 0);
    lines.push(`vault_shim_request_latency_ms_sum ${sum}`);
    lines.push(`vault_shim_request_latency_ms_count ${metrics.request_latency_ms.length}`);
    [100,500,1000,5000].forEach(le => {
      const count = metrics.request_latency_ms.filter(x => x <= le).length;
      lines.push(`vault_shim_request_latency_ms_bucket{le="${le}"} ${count}`);
    });
  }
  return lines.join('\n') + '\n';
}

module.exports = {
  recordRequest,
  incActive,
  decActive,
  getPrometheusMetrics,
};
