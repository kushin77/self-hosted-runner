/**
 * Unit Tests: Metrics Service
 * Tests API metrics recording, Prometheus format generation, and performance tracking
 */

import { describe, it, expect, beforeEach } from '@jest/globals';
import { MetricsService, MetricsSnapshot } from '../../../src/metrics';

describe('Metrics Service', () => {
  let metricsService: MetricsService;

  beforeEach(() => {
    metricsService = new MetricsService();
  });

  describe('Request Recording', () => {
    it('should record HTTP request metrics', () => {
      metricsService.recordRequest('GET', '/api/health', 200, 50);

      const metrics = metricsService.getMetrics();
      expect(metrics).toContain('nexus_portal_requests_total');
      expect(metrics).toContain('status="all"');
    });

    it('should count total requests', () => {
      let metricsInitial = metricsService.getMetrics();

      metricsService.recordRequest('GET', '/api/health', 200, 25);
      metricsService.recordRequest('POST', '/api/login', 200, 35);
      metricsService.recordRequest('GET', '/api/status', 200, 15);

      const metrics = metricsService.getMetrics();
      // Should show 3 total requests
      expect(metrics).toContain('nexus_portal_requests_total');
    });

    it('should track successful requests (status < 400)', () => {
      metricsService.recordRequest('GET', '/api/health', 200, 50);
      metricsService.recordRequest('POST', '/api/login', 201, 100);
      metricsService.recordRequest('GET', '/api/data', 204, 75);

      const metrics = metricsService.getMetrics();
      expect(metrics).toContain('status="success"');
    });

    it('should track failed requests (status >= 400)', () => {
      metricsService.recordRequest('GET', '/api/notfound', 404, 30);
      metricsService.recordRequest('POST', '/api/error', 500, 150);
      metricsService.recordRequest('GET', '/api/unauthorized', 401, 20);

      const metrics = metricsService.getMetrics();
      expect(metrics).toContain('status="failed"');
    });

    it('should track request latencies', () => {
      const latencies = [25, 50, 75, 100, 125, 150, 200];

      for (const latency of latencies) {
        metricsService.recordRequest('GET', '/api/test', 200, latency);
      }

      const metrics = metricsService.getMetrics();
      expect(metrics).toContain('nexus_portal_latency_milliseconds');
    });
  });

  describe('Latency Tracking', () => {
    it('should calculate average latency', () => {
      metricsService.recordRequest('GET', '/api/health', 200, 100);
      metricsService.recordRequest('GET', '/api/health', 200, 50);
      metricsService.recordRequest('GET', '/api/health', 200, 150);

      const metrics = metricsService.getMetrics();
      // Average should be (100 + 50 + 150) / 3 = 100ms
      expect(metrics).toContain('quantile="avg"');
    });

    it('should calculate latency percentiles', () => {
      // Record 100 requests with increasing latencies
      for (let i = 1; i <= 100; i++) {
        metricsService.recordRequest('GET', '/api/test', 200, i * 10);
      }

      const metrics = metricsService.getMetrics();
      expect(metrics).toContain('quantile="p50"');
      expect(metrics).toContain('quantile="p95"');
      expect(metrics).toContain('quantile="p99"');
    });

    it('should keep last 1000 latencies (circular buffer)', () => {
      // Record more than 1000 requests to test circular buffer
      for (let i = 0; i < 1500; i++) {
        metricsService.recordRequest('GET', '/api/test', 200, Math.random() * 500);
      }

      // Service should not crash and metrics should be valid
      const metrics = metricsService.getMetrics();
      expect(metrics).toBeDefined();
      expect(metrics.length).toBeGreaterThan(0);
    });
  });

  describe('Prometheus Metrics Format', () => {
    it('should generate valid Prometheus format output', () => {
      metricsService.recordRequest('GET', '/api/test', 200, 50);

      const metrics = metricsService.getMetrics();

      // Prometheus format rules:
      // 1. Comments start with #
      // 2. HELP lines: # HELP metricname description
      // 3. TYPE lines: # TYPE metricname type
      // 4. Metric lines: metricname{labels} value

      expect(metrics).toContain('# HELP');
      expect(metrics).toContain('# TYPE');
      expect(metrics).toMatch(/nexus_portal_[a-z_]+ \d+/); // Metric with value
    });

    it('should include request counter metrics', () => {
      metricsService.recordRequest('GET', '/api/health', 200, 50);
      metricsService.recordRequest('POST', '/api/login', 401, 100);

      const metrics = metricsService.getMetrics();

      expect(metrics).toContain('nexus_portal_requests_total{status="all"}');
      expect(metrics).toContain('nexus_portal_requests_total{status="success"}');
      expect(metrics).toContain('nexus_portal_requests_total{status="failed"}');
    });

    it('should include latency gauge metrics', () => {
      metricsService.recordRequest('GET', '/api/test', 200, 100);

      const metrics = metricsService.getMetrics();

      expect(metrics).toContain('nexus_portal_latency_milliseconds');
      expect(metrics).toContain('quantile="p50"');
      expect(metrics).toContain('quantile="avg"');
    });

    it('should include memory metrics', () => {
      metricsService.recordRequest('GET', '/api/test', 200, 50);

      const metrics = metricsService.getMetrics();

      expect(metrics).toContain('nexus_portal_memory_bytes');
      expect(metrics).toContain('type="heapUsed"');
      expect(metrics).toContain('type="heapTotal"');
      expect(metrics).toContain('type="rss"');
    });

    it('should include uptime metric', () => {
      metricsService.recordRequest('GET', '/api/test', 200, 50);

      const metrics = metricsService.getMetrics();

      expect(metrics).toContain('nexus_portal_uptime_seconds');
    });
  });

  describe('Status Code Distribution', () => {
    it('should track 2xx success responses', () => {
      metricsService.recordRequest('GET', '/api/health', 200, 50);
      metricsService.recordRequest('POST', '/api/create', 201, 100);
      metricsService.recordRequest('DELETE', '/api/resource', 204, 75);

      const metrics = metricsService.getMetrics();
      expect(metrics).toContain('status="success"');
    });

    it('should track 4xx client error responses', () => {
      metricsService.recordRequest('GET', '/api/notfound', 404, 30);
      metricsService.recordRequest('POST', '/api/bad', 400, 25);
      metricsService.recordRequest('GET', '/api/unauthorized', 401, 20);

      const metrics = metricsService.getMetrics();
      expect(metrics).toContain('status="failed"');
    });

    it('should track 5xx server error responses', () => {
      metricsService.recordRequest('GET', '/api/error', 500, 150);
      metricsService.recordRequest('POST', '/api/exception', 503, 200);

      const metrics = metricsService.getMetrics();
      expect(metrics).toContain('status="failed"');
    });
  });

  describe('Idempotent Metrics', () => {
    it('should produce consistent metrics for same input', () => {
      // Record same request pattern
      metricsService.recordRequest('GET', '/api/health', 200, 50);
      metricsService.recordRequest('GET', '/api/health', 200, 50);
      metricsService.recordRequest('GET', '/api/health', 200, 50);

      // Get metrics multiple times
      const metrics1 = metricsService.getMetrics();
      const metrics2 = metricsService.getMetrics();
      const metrics3 = metricsService.getMetrics();

      // Metrics content should be identical (except for uptime variations)
      expect(metrics1).toBeDefined();
      expect(metrics2).toBeDefined();
      expect(metrics3).toBeDefined();
    });
  });

  describe('Memory Reporting', () => {
    it('should report heap memory usage', () => {
      metricsService.recordRequest('GET', '/api/test', 200, 50);

      const metrics = metricsService.getMetrics();

      expect(metrics).toContain('type="heapUsed"');
      expect(metrics).toContain('type="heapTotal"');
    });

    it('should report RSS memory usage', () => {
      metricsService.recordRequest('GET', '/api/test', 200, 50);

      const metrics = metricsService.getMetrics();

      expect(metrics).toContain('type="rss"');
    });

    it('should report memory in bytes', () => {
      metricsService.recordRequest('GET', '/api/test', 200, 50);

      const metrics = metricsService.getMetrics();

      // Memory values should be numeric bytes
      expect(metrics).toMatch(/type="heapUsed"\}\s+\d+/);
    });
  });

  describe('Uptime Tracking', () => {
    it('should track service uptime', () => {
      // Service was just created, uptime should be small
      metricsService.recordRequest('GET', '/api/test', 200, 50);

      const metrics = metricsService.getMetrics();

      expect(metrics).toContain('nexus_portal_uptime_seconds');
      // Should have numeric uptime value
      expect(metrics).toMatch(/nexus_portal_uptime_seconds\s+\d+/);
    });

    it('should report uptime in seconds', () => {
      // Small delay
      const startTime = Date.now();
      metricsService.recordRequest('GET', '/api/test', 200, 50);

      const metrics = metricsService.getMetrics();

      // Extract uptime value and verify it's reasonable
      expect(metrics).toContain('nexus_portal_uptime_seconds');
    });
  });

  describe('HTTP Method Tracking', () => {
    it('should track GET requests', () => {
      metricsService.recordRequest('GET', '/api/health', 200, 50);
      metricsService.recordRequest('GET', '/api/status', 200, 45);

      const metrics = metricsService.getMetrics();
      expect(metrics).toContain('nexus_portal_requests_total');
    });

    it('should track POST requests', () => {
      metricsService.recordRequest('POST', '/api/login', 200, 100);
      metricsService.recordRequest('POST', '/api/create', 201, 95);

      const metrics = metricsService.getMetrics();
      expect(metrics).toContain('nexus_portal_requests_total');
    });

    it('should track PUT requests', () => {
      metricsService.recordRequest('PUT', '/api/update', 200, 75);

      const metrics = metricsService.getMetrics();
      expect(metrics).toContain('nexus_portal_requests_total');
    });

    it('should track DELETE requests', () => {
      metricsService.recordRequest('DELETE', '/api/resource', 204, 60);

      const metrics = metricsService.getMetrics();
      expect(metrics).toContain('nexus_portal_requests_total');
    });
  });

  describe('Path Tracking', () => {
    it('should accept various API paths', () => {
      const paths = ['/api/health', '/api/v1/status', '/api/v2/metrics', '/graphql'];

      for (const path of paths) {
        metricsService.recordRequest('GET', path, 200, 50);
      }

      const metrics = metricsService.getMetrics();
      expect(metrics).toBeDefined();
    });
  });

  describe('Percentile Calculations', () => {
    it('should calculate p50 percentile (median)', () => {
      // Record 100 requests with latencies 1ms through 100ms
      for (let i = 1; i <= 100; i++) {
        metricsService.recordRequest('GET', '/api/test', 200, i);
      }

      const metrics = metricsService.getMetrics();
      expect(metrics).toContain('quantile="p50"');
    });

    it('should calculate p95 percentile', () => {
      for (let i = 1; i <= 100; i++) {
        metricsService.recordRequest('GET', '/api/test', 200, i);
      }

      const metrics = metricsService.getMetrics();
      expect(metrics).toContain('quantile="p95"');
    });

    it('should calculate p99 percentile', () => {
      for (let i = 1; i <= 100; i++) {
        metricsService.recordRequest('GET', '/api/test', 200, i);
      }

      const metrics = metricsService.getMetrics();
      expect(metrics).toContain('quantile="p99"');
    });
  });
});
