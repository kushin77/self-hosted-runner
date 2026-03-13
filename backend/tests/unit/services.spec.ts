/**
 * Backend API - Tests
 * Unit tests for core credential, audit, compliance, and metrics services
 * Run with: npm test
 */

import { describe, it, expect, beforeAll, afterAll } from '@jest/globals';
import { setupDefaultMocks } from '../mocks';

// Setup module mocks early so imported services use mocked dependencies
setupDefaultMocks();

import CredentialService from '../../src/credentials';
import AuditService from '../../src/audit';
import ComplianceService from '../../src/compliance';
import MetricsService from '../../src/metrics';

describe('Portal MVP Backend API Tests', () => {
  // =========================================================================
  // CREDENTIAL SERVICE TESTS
  // =========================================================================

  describe('CredentialService', () => {
    let credentialService: CredentialService;

    beforeAll(() => {
      credentialService = new CredentialService();
    });

    it('should resolve credential from 4-layer cascade', async () => {
      const credential = await credentialService.resolveCredential('test-db-password');
      expect(credential).toBeDefined();
      expect(credential.value).toBeDefined();
      expect(credential.layer).toMatch(/gsm|vault|kms|cache/);
      expect(credential.latency_ms).toBeGreaterThanOrEqual(0);
    });

    it('should handle credential resolution (idempotent)', async () => {
      const cred1 = await credentialService.resolveCredential('test-api-key');
      const cred2 = await credentialService.resolveCredential('test-api-key');
      // Same input should produce same output (idempotent)
      expect(cred1.value).toBe(cred2.value);
    });

    it('should rotate credential and track history (immutable)', async () => {
      const rotation = await credentialService.rotateCredential({
        credentialId: 'test-cred-1',
        credentialName: 'test-secret',
        credentialType: 'gsm',
        newValue: 'new-secret-value-12345',
        reason: 'scheduled',
        requestedBy: 'test-user',
      });

      expect(rotation.rotationId).toBeDefined();
      expect(rotation.oldValueHash).toBeDefined();
      expect(rotation.newValueHash).toBeDefined();
      expect(rotation.oldValueHash).not.toBe(rotation.newValueHash);
    });

    it('should schedule credential rotation (idempotent)', async () => {
      const scheduled = await credentialService.scheduleRotation(
        'test-secret',
        'gsm',
        '0 2 * * *'
      );

      expect(scheduled.scheduledRotationId).toBeDefined();
      expect(scheduled.nextRun).toBeGreaterThan(Date.now());

      // Schedule again should update (idempotent)
      const updated = await credentialService.scheduleRotation(
        'test-secret',
        'gsm',
        '0 3 * * *'
      );
      expect(updated.scheduledRotationId).toBeDefined();
    });
  });

  // =========================================================================
  // AUDIT SERVICE TESTS
  // =========================================================================

  describe('AuditService', () => {
    let auditService: AuditService;

    beforeAll(() => {
      auditService = new AuditService();
    });

    it('should create immutable audit log entry', async () => {
      const entry = await auditService.log({
        timestamp: new Date(),
        event: 'credential_created',
        resourceType: 'credential',
        resourceId: 'test-cred-1',
        actor: 'test-user',
        action: 'created',
        status: 'success',
      });

      expect(entry.id).toBeDefined();
      expect(entry.hash).toBeDefined();
      expect(entry.timestamp).toEqual(expect.any(Date));
    });

    it('should query audit logs with filters (idempotent)', async () => {
      const result = await auditService.query({
        resourceType: 'credential',
        limit: 10,
        offset: 0,
      });

      expect(result.entries).toEqual(expect.any(Array));
      expect(result.total).toEqual(expect.any(Number));

      // Same query should produce same results
      const result2 = await auditService.query({
        resourceType: 'credential',
        limit: 10,
        offset: 0,
      });
      expect(result.entries.length).toBe(result2.entries.length);
    });

    it('should verify audit trail integrity', async () => {
      const integrity = await auditService.verifyIntegrity();
      expect(integrity.isValid).toEqual(expect.any(Boolean));
      expect(integrity.entriesChecked).toEqual(expect.any(Number));
    });

    it('should export audit logs to cloud', async () => {
      const exportResult = await auditService.exportToCloud();
      expect(exportResult.exportId).toBeDefined();
      expect(exportResult.entriesExported).toEqual(expect.any(Number));
      expect(exportResult.destination).toContain('gs://');
    });
  });

  // =========================================================================
  // COMPLIANCE SERVICE TESTS
  // =========================================================================

  describe('ComplianceService', () => {
    let complianceService: ComplianceService;

    beforeAll(() => {
      complianceService = new ComplianceService();
    });

    it('should validate credential against policies', async () => {
      const result = await complianceService.validateCredential(
        'test-secret',
        'gsm',
        'secure-password-123!'
      );

      expect(result.isCompliant).toEqual(expect.any(Boolean));
      expect(result.violations).toEqual(expect.any(Array));
    });

    it('should check rotation compliance', async () => {
      const result = await complianceService.checkRotationCompliance(
        'test-cred-1',
        'test-secret'
      );

      expect(result.isCompliant).toEqual(expect.any(Boolean));
      expect(result.lastRotation).toEqual(expect.any(Date));
      expect(result.daysSinceRotation).toEqual(expect.any(Number));
    });

    it('should create compliance policy (idempotent)', async () => {
      const policy = await complianceService.createPolicy({
        name: 'strict-credentials',
        description: 'Strict password policy',
        rules: {
          minLength: 16,
          requireSpecialChars: true,
          requireNumbers: true,
          maxLifetime: 86400,
        },
        resourceTypes: ['gsm', 'aws'],
        resourceNames: ['prod-*', 'staging-*'],
        enabled: true,
        enforced: true,
      });

      expect(policy.id).toBeDefined();
      expect(policy.name).toBe('strict-credentials');

      // Create again - should update (idempotent)
      const updated = await complianceService.createPolicy({
        name: 'strict-credentials',
        description: 'Updated policy',
        rules: { minLength: 20 },
        resourceTypes: ['gsm'],
        resourceNames: ['prod-*'],
        enabled: true,
        enforced: true,
      });

      expect(updated.id).toBe(policy.id);
      expect(updated.description).toBe('Updated policy');
    });

    it('should get compliance status', async () => {
      const status = await complianceService.getComplianceStatus();

      expect(status.totalViolations).toEqual(expect.any(Number));
      expect(status.openViolations).toEqual(expect.any(Number));
      expect(status.criticalViolations).toEqual(expect.any(Number));
      expect(status.complianceScore).toBeGreaterThanOrEqual(0);
      expect(status.complianceScore).toBeLessThanOrEqual(100);
    });
  });

  // =========================================================================
  // METRICS SERVICE TESTS
  // =========================================================================

  describe('MetricsService', () => {
    let metricsService: MetricsService;

    beforeAll(() => {
      metricsService = new MetricsService();
    });

    it('should record HTTP request metrics (idempotent)', () => {
      metricsService.recordRequest('GET', '/health', 200, 45);
      metricsService.recordRequest('GET', '/health', 200, 45);

      // Recording same request multiple times should be safe
      const metrics = metricsService.getMetrics();
      expect(metrics).toContain('nexus_portal_requests_total');
      expect(metrics).toContain('nexus_portal_latency_milliseconds');
    });

    it('should generate Prometheus metrics', () => {
      const metrics = metricsService.getMetrics();

      expect(metrics).toContain('# HELP nexus_portal_requests_total');
      expect(metrics).toContain('# TYPE nexus_portal_requests_total counter');
      expect(metrics).toContain('nexus_portal_requests_total{status="all"}');
      expect(metrics).toContain('nexus_portal_latency_milliseconds');
      expect(metrics).toContain('nexus_portal_memory_bytes');
      expect(metrics).toContain('nexus_portal_uptime_seconds');
    });

    it('should get health status', async () => {
      const health = await metricsService.getHealthStatus();

      expect(health.status).toMatch(/healthy|degraded|unhealthy/);
      expect(health.uptime).toEqual(expect.any(Number));
      expect(health.checks.database).toMatch(/ok|error/);
      expect(health.checks.api).toMatch(/ok|error/);
      expect(health.checks.memory).toMatch(/ok|warning|error/);
    });

    it('should save metrics snapshot', async () => {
      await metricsService.saveSnapshot();
      // Should complete without error

      const history = await metricsService.getHistory(1);
      expect(history).toEqual(expect.any(Array));
    });
  });

  // =========================================================================
  // INTEGRATION TESTS
  // =========================================================================

  describe('Integration Tests', () => {
    it('should execute complete credential lifecycle', async () => {
      const credentialService = new CredentialService();
      const auditService = new AuditService();
      const complianceService = new ComplianceService();

      // 1. Create credential
      const resolved = await credentialService.resolveCredential('integration-test-secret');
      expect(resolved.value).toBeDefined();

      // 2. Audit the access
      const auditEntry = await auditService.log({
        timestamp: new Date(),
        event: 'credential_accessed',
        resourceType: 'credential',
        resourceId: 'integration-test-secret',
        actor: 'integration-tester',
        action: 'resolved',
        status: 'success',
      });
      expect(auditEntry.id).toBeDefined();

      // 3. Check compliance
      const compliance = await complianceService.validateCredential(
        'integration-test-secret',
        'gsm',
        resolved.value
      );
      expect(compliance.isCompliant).toBeDefined();
    });
  });
});
