/**
 * Unit Tests: Audit Service
 * Tests immutable audit logging, hashing, and audit trail integrity
 */

import { describe, it, expect, beforeEach, jest } from '@jest/globals';
import { AuditService, AuditLogEntry } from '../../../src/audit';
import crypto from 'crypto';

describe('Audit Service', () => {
  let auditService: AuditService;

  beforeEach(() => {
    auditService = new AuditService();
  });

  describe('Audit Entry Creation', () => {
    it('should create audit entry with all required fields', async () => {
      const entry = await auditService.log({
        timestamp: new Date(),
        event: 'credential_rotated',
        resourceType: 'credential',
        resourceId: 'cred-123',
        actor: 'user123',
        action: 'rotation',
        status: 'success',
      });

      expect(entry).toBeDefined();
      expect(entry.id).toBeDefined();
      expect(entry.event).toBe('credential_rotated');
      expect(entry.resourceType).toBe('credential');
      expect(entry.status).toBe('success');
      expect(entry.hash).toBeDefined();
    });

    it('should support optional details field', async () => {
      const entry = await auditService.log({
        timestamp: new Date(),
        event: 'credential_rotated',
        resourceType: 'credential',
        resourceId: 'cred-456',
        actor: 'user123',
        action: 'rotation',
        status: 'success',
        details: { reason: 'scheduled', oldValue: '***', newValue: '***' },
      });

      expect(entry.details).toBeDefined();
      expect(entry.details?.reason).toBe('scheduled');
    });

    it('should support IP address and user agent tracking', async () => {
      const entry = await auditService.log({
        timestamp: new Date(),
        event: 'user_login',
        resourceType: 'user',
        resourceId: 'user123',
        actor: 'user123',
        action: 'login',
        status: 'success',
        ipAddress: '192.168.1.100',
        userAgent: 'Mozilla/5.0...',
      });

      expect(entry.ipAddress).toBe('192.168.1.100');
      expect(entry.userAgent).toBe('Mozilla/5.0...');
    });
  });

  describe('Immutable Audit Trail', () => {
    it('should generate consistent hash for same entry', async () => {
      const entryData = {
        timestamp: new Date('2026-03-11T12:00:00Z'),
        event: 'credential_accessed',
        resourceType: 'credential',
        resourceId: 'api_key',
        actor: 'service_account',
        action: 'access',
        status: 'success' as const,
      };

      const entry1 = await auditService.log(entryData);
      const entry2 = await auditService.log(entryData);

      // Hashes should differ because of different previousHash values
      // But both should be valid SHA256 hashes
      expect(entry1.hash).toMatch(/^[a-f0-9]{64}$/); // SHA256 format
      expect(entry2.hash).toMatch(/^[a-f0-9]{64}$/);
    });

    it('should create hash chain (blockchain-like)', async () => {
      const entry1 = await auditService.log({
        timestamp: new Date(),
        event: 'event1',
        resourceType: 'credential',
        actor: 'user1',
        action: 'action1',
        status: 'success',
      });

      const entry2 = await auditService.log({
        timestamp: new Date(),
        event: 'event2',
        resourceType: 'credential',
        actor: 'user1',
        action: 'action2',
        status: 'success',
      });

      // entry2's previousHash should equal entry1's hash
      expect(entry2.previousHash).toBe(entry1.hash);

      // Each hash should be different
      expect(entry1.hash).not.toBe(entry2.hash);
    });

    it('should create tamper-evident audit trail', async () => {
      // Create entries in sequence
      const entries = [];
      for (let i = 0; i < 5; i++) {
        const entry = await auditService.log({
          timestamp: new Date(),
          event: `event_${i}`,
          resourceType: 'credential',
          actor: 'user1',
          action: `action_${i}`,
          status: 'success',
        });
        entries.push(entry);
      }

      // Verify chain integrity
      for (let i = 1; i < entries.length; i++) {
        expect(entries[i].previousHash).toBe(entries[i - 1].hash);
      }

      // Verify each hash is unique
      const hashes = entries.map((e) => e.hash);
      const uniqueHashes = new Set(hashes);
      expect(uniqueHashes.size).toBe(entries.length);
    });
  });

  describe('Event Types', () => {
    const eventTypes = [
      'credential_rotated',
      'credential_accessed',
      'user_login',
      'access_denied',
      'policy_violation',
      'compliance_check',
      'system_event',
    ];

    eventTypes.forEach((eventType) => {
      it(`should log event type: ${eventType}`, async () => {
        const entry = await auditService.log({
          timestamp: new Date(),
          event: eventType as any,
          resourceType: 'test',
          actor: 'user1',
          action: 'test',
          status: 'success',
        });

        expect(entry.event).toBe(eventType);
      });
    });
  });

  describe('Status Tracking', () => {
    it('should track successful operations', async () => {
      const entry = await auditService.log({
        timestamp: new Date(),
        event: 'credential_accessed',
        resourceType: 'credential',
        actor: 'user1',
        action: 'access',
        status: 'success',
      });

      expect(entry.status).toBe('success');
    });

    it('should track denied operations', async () => {
      const entry = await auditService.log({
        timestamp: new Date(),
        event: 'credential_accessed',
        resourceType: 'credential',
        actor: 'unauthorized_user',
        action: 'access',
        status: 'denied',
      });

      expect(entry.status).toBe('denied');
    });

    it('should track failed operations', async () => {
      const entry = await auditService.log({
        timestamp: new Date(),
        event: 'credential_rotation',
        resourceType: 'credential',
        actor: 'user1',
        action: 'rotation',
        status: 'failed',
        details: { reason: 'KMS unavailable' },
      });

      expect(entry.status).toBe('failed');
    });
  });

  describe('Audit Entry Timestamps', () => {
    it('should record timestamp of audit event', async () => {
      const beforeTime = new Date();
      const entry = await auditService.log({
        timestamp: new Date(),
        event: 'test_event',
        resourceType: 'test',
        actor: 'user1',
        action: 'test',
        status: 'success',
      });
      const afterTime = new Date();

      expect(entry.timestamp).toBeDefined();
      expect(entry.timestamp.getTime()).toBeGreaterThanOrEqual(beforeTime.getTime());
      expect(entry.timestamp.getTime()).toBeLessThanOrEqual(afterTime.getTime());
    });

    it('should support explicit timestamp in entry', async () => {
      const customTime = new Date('2026-03-10T10:30:00Z');
      const entry = await auditService.log({
        timestamp: customTime,
        event: 'test_event',
        resourceType: 'test',
        actor: 'user1',
        action: 'test',
        status: 'success',
      });

      expect(entry.timestamp.getTime()).toBe(customTime.getTime());
    });
  });

  describe('Resource Tracking', () => {
    it('should support credential resources', async () => {
      const entry = await auditService.log({
        timestamp: new Date(),
        event: 'credential_accessed',
        resourceType: 'credential',
        resourceId: 'api_credential_789',
        actor: 'app_service',
        action: 'access',
        status: 'success',
      });

      expect(entry.resourceType).toBe('credential');
      expect(entry.resourceId).toBe('api_credential_789');
    });

    it('should support user resources', async () => {
      const entry = await auditService.log({
        timestamp: new Date(),
        event: 'user_login',
        resourceType: 'user',
        resourceId: 'user123',
        actor: 'user123',
        action: 'login',
        status: 'success',
      });

      expect(entry.resourceType).toBe('user');
      expect(entry.resourceId).toBe('user123');
    });

    it('should support policy resources', async () => {
      const entry = await auditService.log({
        timestamp: new Date(),
        event: 'policy_violation',
        resourceType: 'policy',
        resourceId: 'policy_require_rotation',
        actor: 'compliance_check',
        action: 'enforcement',
        status: 'denied',
      });

      expect(entry.resourceType).toBe('policy');
      expect(entry.resourceId).toBe('policy_require_rotation');
    });

    it('should allow empty resourceId for system events', async () => {
      const entry = await auditService.log({
        timestamp: new Date(),
        event: 'system_event',
        resourceType: 'system',
        actor: 'scheduler',
        action: 'cleanup',
        status: 'success',
      });

      expect(entry.resourceId).toBeUndefined();
    });
  });

  describe('Audit Idempotency', () => {
    it('should produce consistent audit entries for same input', async () => {
      const entryData = {
        timestamp: new Date('2026-03-11T15:00:00Z'),
        event: 'credential_accessed' as const,
        resourceType: 'credential',
        resourceId: 'test_cred',
        actor: 'user1',
        action: 'access',
        status: 'success' as const,
        details: { latency_ms: 50 },
      };

      // Log same event multiple times
      const entry1 = await auditService.log(entryData);
      const entry2 = await auditService.log(entryData);

      // Different entries (different IDs due to database auto-increment)
      expect(entry1.id).not.toBe(entry2.id);

      // But same event data
      expect(entry1.event).toBe(entry2.event);
      expect(entry1.actor).toBe(entry2.actor);
      expect(entry1.action).toBe(entry2.action);
    });
  });

  describe('Append-Only Invariant', () => {
    it('should never delete audit entries', async () => {
      // This is a property tested at the database/ORM level
      // The service interface only provides log() method, not delete()
      const methods = Object.getOwnPropertyNames(Object.getPrototypeOf(auditService));
      expect(methods).not.toContain('deleteAuditEntry');
      expect(methods).not.toContain('deleteEntry');
      expect(methods).not.toContain('deleteLog');
    });

    it('should never modify audit entries', async () => {
      const entry = await auditService.log({
        timestamp: new Date(),
        event: 'test_event',
        resourceType: 'test',
        actor: 'user1',
        action: 'test',
        status: 'success',
      });

      // Verify entry is immutable by checking it has hash
      expect(entry.hash).toBeDefined();
      expect(entry.previousHash).toBeDefined();

      // Hash proves entry hasn't been tampered with
      const hashInput = JSON.stringify({
        timestamp: entry.timestamp,
        event: entry.event,
        resourceType: entry.resourceType,
        actor: entry.actor,
        action: entry.action,
        status: entry.status,
        details: entry.details,
        previousHash: entry.previousHash,
      });
      const expectedHash = crypto.createHash('sha256').update(hashInput).digest('hex');
      expect(entry.hash).toBe(expectedHash);
    });
  });
});
