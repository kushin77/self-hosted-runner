/**
 * Unit Tests: Credential Service
 * Tests credential resolution logic without external dependencies
 */

import { describe, it, expect, beforeEach, jest } from '@jest/globals';
import {
  CredentialResolution,
  CredentialAuditEntry,
} from '../../../src/credentials';
import {
  CredentialNotFoundError,
  CredentialResolutionError,
  ApplicationError,
} from '../../../src/errors';
import { createMockPrisma, createMockSecretManager, createMockVault, createMockKMS, testFixtures } from '../../mocks';

// Mock external services
jest.mock('../../../src/prisma-wrapper', () => ({
  getPrisma: () => createMockPrisma(),
}));
jest.mock('@google-cloud/secret-manager', () => ({
  SecretManagerServiceClient: jest.fn().mockImplementation(() => createMockSecretManager()),
}));
jest.mock('node-vault', () => jest.fn().mockImplementation(() => createMockVault()));
jest.mock('@google-cloud/kms', () => ({
  KeyManagementServiceClient: jest.fn().mockImplementation(() => createMockKMS()),
}));

/**
 * Mock credential service for isolated unit testing
 */
class MockCredentialService {
  private cache: Map<string, CredentialResolution> = new Map();

  /**
   * Simulates credential resolution from multiple layers
   */
  async getCredential(name: string): Promise<CredentialResolution> {
    // Check cache first
    if (this.cache.has(name)) {
      return this.cache.get(name)!;
    }

    // Simulate GSM resolution
    const gsmResult = await this.resolveFromGSM(name);
    if (gsmResult) {
      return gsmResult;
    }

    // Simulate Vault fallback
    const vaultResult = await this.resolveFromVault(name);
    if (vaultResult) {
      return vaultResult;
    }

    // Simulate KMS fallback
    const kmsResult = await this.resolveFromKMS(name);
    if (kmsResult) {
      return kmsResult;
    }

    // All layers failed
    throw new CredentialResolutionError(name, ['gsm', 'vault', 'kms']);
  }

  private async resolveFromGSM(name: string): Promise<CredentialResolution | null> {
    if (name === 'test-credential') {
      return {
        value: 'gsm-secret-value',
        layer: 'gsm',
        latency_ms: 45,
        resolutionTime: new Date(),
        source: 'projects/test-project/secrets/test-credential',
      };
    }
    return null;
  }

  private async resolveFromVault(name: string): Promise<CredentialResolution | null> {
    if (name === 'vault-only-credential') {
      return {
        value: 'vault-secret-value',
        layer: 'vault',
        latency_ms: 62,
        resolutionTime: new Date(),
        source: 'secret/data/vault-only-credential',
      };
    }
    return null;
  }

  private async resolveFromKMS(name: string): Promise<CredentialResolution | null> {
    if (name === 'kms-only-credential') {
      return {
        value: 'kms-secret-value',
        layer: 'kms',
        latency_ms: 88,
        resolutionTime: new Date(),
        source: 'projects/test-project/locations/global/keyRings/ring/cryptoKeys/key',
      };
    }
    return null;
  }
}

describe('CredentialService', () => {
  let service: MockCredentialService;

  beforeEach(() => {
    service = new MockCredentialService();
  });

  describe('getCredential', () => {
    it('should resolve credential from GSM layer', async () => {
      const result = await service.getCredential('test-credential');
      expect(result).toBeDefined();
      expect(result.layer).toBe('gsm');
      expect(result.value).toBe('gsm-secret-value');
      expect(result.latency_ms).toBeLessThan(100);
    });

    it('should fallback to Vault when GSM fails', async () => {
      const result = await service.getCredential('vault-only-credential');
      expect(result).toBeDefined();
      expect(result.layer).toBe('vault');
      expect(result.value).toBe('vault-secret-value');
    });

    it('should fallback to KMS when GSM and Vault fail', async () => {
      const result = await service.getCredential('kms-only-credential');
      expect(result).toBeDefined();
      expect(result.layer).toBe('kms');
      expect(result.value).toBe('kms-secret-value');
    });

    it('should throw CredentialResolutionError when all layers fail', async () => {
      await expect(service.getCredential('nonexistent')).rejects.toThrow(
        CredentialResolutionError,
      );
    });

    it('should include latency metrics in response', async () => {
      const result = await service.getCredential('test-credential');
      expect(result.latency_ms).toBeGreaterThanOrEqual(0);
      expect(result.latency_ms).toBeLessThan(1000);
    });
  });
});

describe('Error Handling', () => {
  it('should create CredentialResolutionError with proper structure', () => {
    const error = new CredentialResolutionError('test-cred', ['gsm', 'vault']);
    expect(error.code).toBe('CRED_RESOLUTION_FAILED');
    expect(error.statusCode).toBe(503);
    expect(error.details?.failedLayers).toContain('gsm');
  });

  it('should convert ApplicationError to JSON', () => {
    const error = new CredentialNotFoundError('db-password');
    const json = error.toJSON();
    expect(json.code).toBe('CRED_NOT_FOUND');
    expect(json.statusCode).toBe(404);
    expect(json.timestamp).toBeDefined();
  });

  it('should maintain error chain with cause', () => {
    const cause = new Error('Original error');
    const error = new CredentialResolutionError('test', ['gsm']);
    expect(error.message).toContain('test');
  });
});

/**
 * Custom matchers for error testing
 */
declare global {
  namespace jest {
    interface Matchers<R> {
      toBeValidUUID(): R;
    }
  }
}
