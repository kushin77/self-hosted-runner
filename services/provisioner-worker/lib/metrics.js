"use strict";

/**
 * Prometheus Metrics for Provisioner-Worker Service
 * Provides operational visibility into job processing, performance, and system health
 */

const os = require('os');

// Metric storage (in-memory Prometheus format)
const metrics = {
  // Counters
  jobs_processed_total: 0,
  jobs_succeeded_total: 0,
  jobs_failed_total: 0,
  jobs_duplicated_total: 0,
  terraform_applies_total: 0,
  terraform_errors_total: 0,
  
  // Gauges
  queue_depth: 0,
  active_jobs: 0,
  last_job_duration_ms: 0,
  
  // Histograms (stored as arrays for percentile calculation)
  job_processing_latency_ms: [],
  terraform_apply_latency_ms: [],
  jobstore_write_latency_ms: [],
  
  // Timestamps
  last_job_completed_at: null,
  loop_started_at: new Date().toISOString(),
  
  // State
  loop_running: true,
  vault_connected: false,
  jobstore_operational: true,
};

/**
 * Record job processing completion
 * @param {string} status - 'succeeded', 'failed', 'duplicated'
 * @param {number} duration_ms - Time taken in milliseconds
 */
function recordJobCompletion(status, duration_ms) {
  metrics.jobs_processed_total++;
  
  if (status === 'succeeded') {
    metrics.jobs_succeeded_total++;
  } else if (status === 'failed') {
    metrics.jobs_failed_total++;
  } else if (status === 'duplicated') {
    metrics.jobs_duplicated_total++;
  }
  
  metrics.last_job_duration_ms = duration_ms;
  metrics.last_job_completed_at = new Date().toISOString();
  metrics.job_processing_latency_ms.push(duration_ms);
  
  // Keep only last 1000 samples for percentile calculation
  if (metrics.job_processing_latency_ms.length > 1000) {
    metrics.job_processing_latency_ms.shift();
  }
}

/**
 * Record Terraform apply operation
 * @param {number} duration_ms - Time taken in milliseconds
 * @param {boolean} success - Whether apply succeeded
 */
function recordTerraformApply(duration_ms, success) {
  metrics.terraform_applies_total++;
  if (!success) {
    metrics.terraform_errors_total++;
  }
  
  metrics.terraform_apply_latency_ms.push(duration_ms);
  if (metrics.terraform_apply_latency_ms.length > 1000) {
    metrics.terraform_apply_latency_ms.shift();
  }
}

/**
 * Record jobStore write operation
 * @param {number} duration_ms - Time taken in milliseconds
 */
function recordJobStoreWrite(duration_ms) {
  metrics.jobstore_write_latency_ms.push(duration_ms);
  if (metrics.jobstore_write_latency_ms.length > 1000) {
    metrics.jobstore_write_latency_ms.shift();
  }
}

/**
 * Update queue depth gauge
 * @param {number} depth - Number of jobs in queue
 */
function updateQueueDepth(depth) {
  metrics.queue_depth = depth;
}

/**
 * Update active jobs gauge
 * @param {number} count - Number of jobs currently being processed
 */
function updateActiveJobs(count) {
  metrics.active_jobs = count;
}

/**
 * Update Vault connection status
 * @param {boolean} connected - Whether Vault is accessible
 */
function setVaultConnected(connected) {
  metrics.vault_connected = connected;
}

/**
 * Update jobStore operational status
 * @param {boolean} operational - Whether jobStore is functioning
 */
function setJobStoreOperational(operational) {
  metrics.jobstore_operational = operational;
}

/**
 * Calculate percentile from sorted array
 * @param {number[]} arr - Sorted array of values
 * @param {number} p - Percentile (0-100)
 */
function percentile(arr, p) {
  if (arr.length === 0) return 0;
  const sorted = [...arr].sort((a, b) => a - b);
  const index = Math.ceil((p / 100) * sorted.length) - 1;
  return sorted[Math.max(0, index)];
}

/**
 * Get current metrics in Prometheus text format
 * @returns {string} Prometheus metrics in text format
 */
function getPrometheusMetrics() {
  const lines = [];
  
  // HELP and TYPE metadata
  lines.push('# HELP provisioner_jobs_processed_total Total jobs processed');
  lines.push('# TYPE provisioner_jobs_processed_total counter');
  lines.push(`provisioner_jobs_processed_total ${metrics.jobs_processed_total}`);
  
  lines.push('# HELP provisioner_jobs_succeeded_total Total jobs successfully provisioned');
  lines.push('# TYPE provisioner_jobs_succeeded_total counter');
  lines.push(`provisioner_jobs_succeeded_total ${metrics.jobs_succeeded_total}`);
  
  lines.push('# HELP provisioner_jobs_failed_total Total jobs that failed');
  lines.push('# TYPE provisioner_jobs_failed_total counter');
  lines.push(`provisioner_jobs_failed_total ${metrics.jobs_failed_total}`);
  
  lines.push('# HELP provisioner_jobs_duplicated_total Total duplicate jobs rejected');
  lines.push('# TYPE provisioner_jobs_duplicated_total counter');
  lines.push(`provisioner_jobs_duplicated_total ${metrics.jobs_duplicated_total}`);
  
  lines.push('# HELP provisioner_terraform_applies_total Total Terraform apply operations');
  lines.push('# TYPE provisioner_terraform_applies_total counter');
  lines.push(`provisioner_terraform_applies_total ${metrics.terraform_applies_total}`);
  
  lines.push('# HELP provisioner_terraform_errors_total Total Terraform apply errors');
  lines.push('# TYPE provisioner_terraform_errors_total counter');
  lines.push(`provisioner_terraform_errors_total ${metrics.terraform_errors_total}`);
  
  // Gauges
  lines.push('# HELP provisioner_queue_depth Current number of jobs in queue');
  lines.push('# TYPE provisioner_queue_depth gauge');
  lines.push(`provisioner_queue_depth ${metrics.queue_depth}`);
  
  lines.push('# HELP provisioner_active_jobs Current number of jobs being processed');
  lines.push('# TYPE provisioner_active_jobs gauge');
  lines.push(`provisioner_active_jobs ${metrics.active_jobs}`);
  
  lines.push('# HELP provisioner_last_job_duration_ms Duration of last completed job');
  lines.push('# TYPE provisioner_last_job_duration_ms gauge');
  lines.push(`provisioner_last_job_duration_ms ${metrics.last_job_duration_ms}`);
  
  lines.push('# HELP provisioner_vault_connected Vault connectivity status (1=connected, 0=disconnected)');
  lines.push('# TYPE provisioner_vault_connected gauge');
  lines.push(`provisioner_vault_connected ${metrics.vault_connected ? 1 : 0}`);
  
  lines.push('# HELP provisioner_jobstore_operational JobStore operational status (1=operational, 0=error)');
  lines.push('# TYPE provisioner_jobstore_operational gauge');
  lines.push(`provisioner_jobstore_operational ${metrics.jobstore_operational ? 1 : 0}`);
  
  // Latency Histograms
  if (metrics.job_processing_latency_ms.length > 0) {
    lines.push('# HELP provisioner_job_processing_latency_ms Job processing latency in milliseconds');
    lines.push('# TYPE provisioner_job_processing_latency_ms histogram');
    
    const sum = metrics.job_processing_latency_ms.reduce((a, b) => a + b, 0);
    lines.push(`provisioner_job_processing_latency_ms_bucket{le="100"} ${metrics.job_processing_latency_ms.filter(x => x <= 100).length}`);
    lines.push(`provisioner_job_processing_latency_ms_bucket{le="500"} ${metrics.job_processing_latency_ms.filter(x => x <= 500).length}`);
    lines.push(`provisioner_job_processing_latency_ms_bucket{le="1000"} ${metrics.job_processing_latency_ms.filter(x => x <= 1000).length}`);
    lines.push(`provisioner_job_processing_latency_ms_bucket{le="5000"} ${metrics.job_processing_latency_ms.filter(x => x <= 5000).length}`);
    lines.push(`provisioner_job_processing_latency_ms_bucket{le="+Inf"} ${metrics.job_processing_latency_ms.length}`);
    lines.push(`provisioner_job_processing_latency_ms_sum ${sum}`);
    lines.push(`provisioner_job_processing_latency_ms_count ${metrics.job_processing_latency_ms.length}`);
  }
  
  if (metrics.terraform_apply_latency_ms.length > 0) {
    lines.push('# HELP provisioner_terraform_apply_latency_ms Terraform apply operation latency in milliseconds');
    lines.push('# TYPE provisioner_terraform_apply_latency_ms histogram');
    
    const sum = metrics.terraform_apply_latency_ms.reduce((a, b) => a + b, 0);
    lines.push(`provisioner_terraform_apply_latency_ms_bucket{le="500"} ${metrics.terraform_apply_latency_ms.filter(x => x <= 500).length}`);
    lines.push(`provisioner_terraform_apply_latency_ms_bucket{le="2000"} ${metrics.terraform_apply_latency_ms.filter(x => x <= 2000).length}`);
    lines.push(`provisioner_terraform_apply_latency_ms_bucket{le="5000"} ${metrics.terraform_apply_latency_ms.filter(x => x <= 5000).length}`);
    lines.push(`provisioner_terraform_apply_latency_ms_bucket{le="10000"} ${metrics.terraform_apply_latency_ms.filter(x => x <= 10000).length}`);
    lines.push(`provisioner_terraform_apply_latency_ms_bucket{le="+Inf"} ${metrics.terraform_apply_latency_ms.length}`);
    lines.push(`provisioner_terraform_apply_latency_ms_sum ${sum}`);
    lines.push(`provisioner_terraform_apply_latency_ms_count ${metrics.terraform_apply_latency_ms.length}`);
  }
  
  // System metrics
  lines.push('# HELP process_uptime_seconds Process uptime in seconds');
  lines.push('# TYPE process_uptime_seconds gauge');
  lines.push(`process_uptime_seconds ${Math.floor(process.uptime())}`);
  
  lines.push('# HELP process_resident_memory_bytes Resident memory usage in bytes');
  lines.push('# TYPE process_resident_memory_bytes gauge');
  if (process.memoryUsage) {
    lines.push(`process_resident_memory_bytes ${process.memoryUsage().rss}`);
  }
  
  lines.push('# HELP system_load_average System load average');
  lines.push('# TYPE system_load_average gauge');
  const loadAvg = os.loadavg();
  lines.push(`system_load_average{interval="1m"} ${loadAvg[0]}`);
  lines.push(`system_load_average{interval="5m"} ${loadAvg[1]}`);
  lines.push(`system_load_average{interval="15m"} ${loadAvg[2]}`);
  
  return lines.join('\n') + '\n';
}

/**
 * Get summary statistics for operational monitoring
 */
function getSummaryStats() {
  const jobLatencies = metrics.job_processing_latency_ms;
  const tfLatencies = metrics.terraform_apply_latency_ms;
  
  return {
    uptime: new Date().toISOString(),
    jobs: {
      processed: metrics.jobs_processed_total,
      succeeded: metrics.jobs_succeeded_total,
      failed: metrics.jobs_failed_total,
      duplicated: metrics.jobs_duplicated_total,
      successRate: metrics.jobs_processed_total > 0 
        ? (metrics.jobs_succeeded_total / metrics.jobs_processed_total * 100).toFixed(2) + '%'
        : 'N/A',
    },
    queue: {
      depth: metrics.queue_depth,
      activeJobs: metrics.active_jobs,
    },
    latency: {
      lastJob_ms: metrics.last_job_duration_ms,
      job_p50_ms: jobLatencies.length > 0 ? percentile(jobLatencies, 50) : 0,
      job_p95_ms: jobLatencies.length > 0 ? percentile(jobLatencies, 95) : 0,
      job_p99_ms: jobLatencies.length > 0 ? percentile(jobLatencies, 99) : 0,
      terraform_p50_ms: tfLatencies.length > 0 ? percentile(tfLatencies, 50) : 0,
      terraform_p95_ms: tfLatencies.length > 0 ? percentile(tfLatencies, 95) : 0,
    },
    health: {
      vaultConnected: metrics.vault_connected,
      jobstoreOperational: metrics.jobstore_operational,
    },
    lastJobCompleted: metrics.last_job_completed_at,
  };
}

module.exports = {
  recordJobCompletion,
  recordTerraformApply,
  recordJobStoreWrite,
  updateQueueDepth,
  updateActiveJobs,
  setVaultConnected,
  setJobStoreOperational,
  getPrometheusMetrics,
  getSummaryStats,
  metrics,
};
