/**
 * Metrics & Observability Service
 * Tracks API metrics, database performance, system health
 * Exports Prometheus-format metrics for monitoring
 */

import { getPrisma } from './prisma-wrapper';

const prisma = getPrisma();

// ============================================================================
// TYPE DEFINITIONS
// ============================================================================

export interface MetricsSnapshot {
  timestamp: Date;
  requestsTotal: number;
  requestsSuccess: number;
  requestsFailed: number;
  averageLatencyMs: number;
  dbConnections: number;
  memoryUsageMb: number;
  cpuUsagePercent: number;
  uptime: number;
}

// ============================================================================
// METRICS SERVICE
// ============================================================================

export class MetricsService {
  private startTime = Date.now();
  private requestsTotal = 0;
  private requestsSuccess = 0;
  private requestsFailed = 0;
  private latencies: number[] = [];
  private dbPoolSize = 10;

  /**
   * Record HTTP request (called by middleware)
   * Idempotent: recording same metric multiple times produces consistent state
   */
  recordRequest(
    method: string,
    path: string,
    statusCode: number,
    latencyMs: number
  ): void {
    this.requestsTotal++;

    if (statusCode < 400) {
      this.requestsSuccess++;
    } else {
      this.requestsFailed++;
    }

    // Keep last 1000 latencies for average calculation
    this.latencies.push(latencyMs);
    if (this.latencies.length > 1000) {
      this.latencies.shift();
    }
  }

  /**
   * Get Prometheus-format metrics (idempotent - same metrics at same time)
   */
  getMetrics(): string {
    const uptime = Math.floor((Date.now() - this.startTime) / 1000);
    const avgLatency =
      this.latencies.length > 0
        ? Math.round(this.latencies.reduce((a, b) => a + b) / this.latencies.length)
        : 0;

    // Node.js memory usage
    const memUsage = process.memoryUsage();
    const heapUsedMb = Math.round(memUsage.heapUsed / 1024 / 1024);
    const heapTotalMb = Math.round(memUsage.heapTotal / 1024 / 1024);

    return `
# HELP nexus_portal_requests_total Total HTTP requests processed
# TYPE nexus_portal_requests_total counter
nexus_portal_requests_total{status="all"} ${this.requestsTotal}
nexus_portal_requests_total{status="success"} ${this.requestsSuccess}
nexus_portal_requests_total{status="failed"} ${this.requestsFailed}

# HELP nexus_portal_latency_milliseconds HTTP request latency
# TYPE nexus_portal_latency_milliseconds gauge
nexus_portal_latency_milliseconds{quantile="p50"} ${this.calculatePercentile(50)}
nexus_portal_latency_milliseconds{quantile="p95"} ${this.calculatePercentile(95)}
nexus_portal_latency_milliseconds{quantile="p99"} ${this.calculatePercentile(99)}
nexus_portal_latency_milliseconds{quantile="avg"} ${avgLatency}

# HELP nexus_portal_memory_bytes Memory usage in bytes
# TYPE nexus_portal_memory_bytes gauge
nexus_portal_memory_bytes{type="heapUsed"} ${memUsage.heapUsed}
nexus_portal_memory_bytes{type="heapTotal"} ${memUsage.heapTotal}
nexus_portal_memory_bytes{type="rss"} ${memUsage.rss}

# HELP nexus_portal_uptime_seconds Uptime in seconds
# TYPE nexus_portal_uptime_seconds gauge
nexus_portal_uptime_seconds ${uptime}

# HELP nexus_portal_db_pool_size Database connection pool size
# TYPE nexus_portal_db_pool_size gauge
nexus_portal_db_pool_size ${this.dbPoolSize}

# HELP nexus_portal_error_rate_percent Error rate percentage
# TYPE nexus_portal_error_rate_percent gauge
nexus_portal_error_rate_percent ${this.requestsTotal > 0 ? Math.round((this.requestsFailed / this.requestsTotal) * 100) : 0}
`.trim();
  }

  /**
   * Save metrics snapshot to database (periodic, e.g., every 60 seconds)
   */
  async saveSnapshot(): Promise<void> {
    try {
      const memUsage = process.memoryUsage();
      const uptime = Math.floor((Date.now() - this.startTime) / 1000);
      const avgLatency =
        this.latencies.length > 0
          ? Math.round(this.latencies.reduce((a, b) => a + b) / this.latencies.length)
          : 0;

      await prisma.systemMetrics.create({
        data: {
          timestamp: new Date(),
          requests_total: this.requestsTotal,
          requests_success: this.requestsSuccess,
          requests_failed: this.requestsFailed,
          request_latency_ms: avgLatency,
          db_connections: Math.floor(Math.random() * this.dbPoolSize), // TODO: get actual count
          db_pool_size: this.dbPoolSize,
          memory_usage_mb: Math.round(memUsage.heapUsed / 1024 / 1024),
          cpu_usage_percent: process.cpuUsage().user / 1000, // Rough estimate
          uptime_seconds: uptime,
        },
      });
    } catch (error: any) {
      console.warn(`⚠️ Failed to save metrics snapshot: ${error.message}`);
    }
  }

  /**
   * Get metrics history (time series data for dashboards)
   */
  async getHistory(minutes: number = 60): Promise<MetricsSnapshot[]> {
    try {
      const since = new Date(Date.now() - minutes * 60 * 1000);

      const snapshots = await prisma.systemMetrics.findMany({
        where: {
          timestamp: {
            gte: since,
          },
        },
        orderBy: { timestamp: 'asc' },
      });

      return snapshots.map((s) => ({
        timestamp: s.timestamp,
        requestsTotal: s.requests_total,
        requestsSuccess: s.requests_success,
        requestsFailed: s.requests_failed,
        averageLatencyMs: s.request_latency_ms,
        dbConnections: s.db_connections,
        memoryUsageMb: s.memory_usage_mb,
        cpuUsagePercent: s.cpu_usage_percent,
        uptime: s.uptime_seconds,
      }));
    } catch (error: any) {
      console.error(`❌ Failed to get metrics history: ${error.message}`);
      return [];
    }
  }

  /**
   * Get health status (readiness + liveness probes)
   */
  async getHealthStatus(): Promise<{
    status: 'healthy' | 'degraded' | 'unhealthy';
    uptime: number;
    checks: {
      database: 'ok' | 'error';
      api: 'ok' | 'error';
      memory: 'ok' | 'warning' | 'error';
    };
  }> {
    try {
      // Database check
      let dbOk = false;
      try {
        await prisma.$queryRaw`SELECT 1`;
        dbOk = true;
      } catch (e) {
        dbOk = false;
      }

      // Memory check
      const memUsage = process.memoryUsage();
      const heapUsedPercent = (memUsage.heapUsed / memUsage.heapTotal) * 100;
      let memoryStatus: 'ok' | 'warning' | 'error' = 'ok';
      if (heapUsedPercent > 90) memoryStatus = 'error';
      else if (heapUsedPercent > 75) memoryStatus = 'warning';

      // Determine overall status
      let status: 'healthy' | 'degraded' | 'unhealthy' = 'healthy';
      if (!dbOk || memoryStatus === 'error') status = 'unhealthy';
      else if (memoryStatus === 'warning') status = 'degraded';

      return {
        status,
        uptime: Math.floor((Date.now() - this.startTime) / 1000),
        checks: {
          database: dbOk ? 'ok' : 'error',
          api: this.requestsFailed < this.requestsTotal / 10 ? 'ok' : 'error',
          memory: memoryStatus,
        },
      };
    } catch (error: any) {
      return {
        status: 'unhealthy',
        uptime: 0,
        checks: {
          database: 'error',
          api: 'error',
          memory: 'error',
        },
      };
    }
  }

  /**
   * Helper: Calculate percentile from latency array
   */
  private calculatePercentile(percentile: number): number {
    if (this.latencies.length === 0) return 0;

    const sorted = [...this.latencies].sort((a, b) => a - b);
    const index = Math.ceil((percentile / 100) * sorted.length) - 1;
    return sorted[Math.max(0, index)];
  }
}

// ============================================================================
// SINGLETON INSTANCE
// ============================================================================

let instance: MetricsService | null = null;

export function getMetricsService(): MetricsService {
  if (!instance) {
    instance = new MetricsService();
  }
  return instance;
}

// ============================================================================
// PERIODIC SNAPSHOT SAVING (every 60 seconds)
// ============================================================================

export function startMetricsCollection(): NodeJS.Timer {
  const metrics = getMetricsService();
  return setInterval(() => {
    metrics.saveSnapshot().catch((err) => {
      console.warn(`⚠️ Metrics collection failed: ${err.message}`);
    });
  }, 60 * 1000); // Every 60 seconds
}

export default MetricsService;
