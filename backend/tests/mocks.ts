/**
 * Jest Mock Utilities
 * Provides mock implementations for external services (Prisma, GCP, Vault, KMS)
 */

import { jest } from '@jest/globals';

// ============================================================================
// PRISMA MOCK
// ============================================================================

export const createMockPrisma = () => {
  let auditLogCounter = 0;
  let credentialCounter = 0;
  
  return {
    auditLog: {
      create: jest.fn(async (input: any) => {
        const data = input.data || {};
        return {
          id: `audit-${++auditLogCounter}`,
          created_at: data.created_at || new Date(),
          event: data.event || 'test_event',
          resource_type: data.resource_type || 'test',
          resource_id: data.resource_id || null,
          actor_id: data.actor_id || 'test_user',
          action: data.action || 'test',
          details: data.details || null,
          hash: data.hash || 'abc123',
          previous_hash: data.previous_hash || null,
        };
      }),
      findFirst: jest.fn(async () => ({
        id: 'audit-1',
        hash: 'abc123',
        created_at: new Date(),
      })),
      findMany: jest.fn(async () => []),
    },
    credentialPolicy: {
      findMany: jest.fn(async () => []),
      findUnique: jest.fn(async () => null),
      create: jest.fn(async () => ({
        id: 'policy-1',
        name: 'test_policy',
        rules: {},
      })),
    },
    credential: {
      findUnique: jest.fn(async () => ({
        id: 'cred-1',
        name: 'test_cred',
        type: 'password',
      })),
      findMany: jest.fn(async () => []),
      create: jest.fn(async (input: any) => {
        const data = input.data || {};
        return {
          id: `cred-${++credentialCounter}`,
          name: data.name || 'test_cred',
          type: data.type || 'password',
        };
      }),
      update: jest.fn(async (input: any) => {
        const data = input.data || {};
        return {
          id: input.where?.id || 'cred-1',
          name: data.name || 'test_cred',
          type: data.type || 'password',
        };
      }),
    },
    $executeRaw: jest.fn(async () => undefined),
    $queryRaw: jest.fn(async () => []),
  };
};

// ============================================================================
// GCP SECRET MANAGER MOCK
// ============================================================================

export const createMockSecretManager = () => ({
  accessSecret: jest.fn(async () => ({
    payload: { data: Buffer.from('test-secret-value') },
  })),
  getSecret: jest.fn(async () => ({ name: 'test-secret' })),
  addSecretVersion: jest.fn(async () => ({ name: 'test-version' })),
  createSecret: jest.fn(async () => ({ name: 'test-secret' })),
});

// ============================================================================
// VAULT MOCK
// ============================================================================

export const createMockVault = () => ({
  read: jest.fn(async () => ({ 
    data: { data: { value: 'vault-secret-value' } } 
  })),
  write: jest.fn(async () => ({ 
    data: { data: { version: 1 } } 
  })),
  destroy: jest.fn(async () => ({})),
});

// ============================================================================
// KMS MOCK
// ============================================================================

export const createMockKMS = () => ({
  decrypt: jest.fn(async () => ({
    plaintext: Buffer.from('decrypted-value'),
  })),
  encrypt: jest.fn(async () => ({
    ciphertext: Buffer.from('encrypted-value'),
  })),
});

// ============================================================================
// JWT MOCK
// ============================================================================

export const createMockJWT = () => ({
  sign: jest.fn(() => 'mock-jwt-token'),
  verify: jest.fn(() => ({
    userId: 'test-user',
    email: 'test@example.com',
    role: 'admin',
    iat: Math.floor(Date.now() / 1000),
    exp: Math.floor(Date.now() / 1000) + 86400,
  })),
});

// ============================================================================
// EXPRESS MOCK
// ============================================================================

export const createMockRequest = (overrides = {}) => ({
  headers: {},
  method: 'GET',
  path: '/',
  query: {},
  body: {},
  params: {},
  ...overrides,
});

export const createMockResponse = () => {
  const res = {
    status: jest.fn().mockReturnThis(),
    json: jest.fn().mockReturnThis(),
    send: jest.fn().mockReturnThis(),
    setHeader: jest.fn().mockReturnThis(),
    getHeader: jest.fn().mockReturnValue(undefined),
    end: jest.fn().mockReturnThis(),
  };
  return res;
};

export const createMockNext = () => jest.fn();

// ============================================================================
// FILE SYSTEM MOCK
// ============================================================================

export const createMockFS = () => ({
  readFileSync: jest.fn(() => '{"id":"abc123","hash":"def456"}'),
  writeFileSync: jest.fn(),
  appendFileSync: jest.fn(),
  existsSync: jest.fn(() => true),
  mkdirSync: jest.fn(),
});

// ============================================================================
// CRYPTO MOCK
// ============================================================================

export const createMockCrypto = () => ({
  createHash: jest.fn().mockImplementation((algo) => ({
    update: jest.fn().mockReturnThis(),
    digest: jest.fn().mockReturnValue('mock-hash-abc123'),
  })),
  randomBytes: jest.fn().mockReturnValue(Buffer.from('randomness')),
  createHmac: jest.fn().mockImplementation(() => ({
    update: jest.fn().mockReturnThis(),
    digest: jest.fn().mockReturnValue('mock-hmac'),
  })),
});

// ============================================================================
// LOGGER MOCK
// ============================================================================

export const createMockLogger = () => ({
  info: jest.fn(),
  warn: jest.fn(),
  error: jest.fn(),
  debug: jest.fn(),
  log: jest.fn(),
});

// ============================================================================
// REDIS MOCK
// ============================================================================

export const createMockRedis = () => ({
  get: jest.fn(async () => null),
  set: jest.fn(async () => 'OK'),
  del: jest.fn(async () => 1),
  exists: jest.fn(async () => 0),
  expire: jest.fn(async () => 1),
  ttl: jest.fn(async () => -1),
});

// ============================================================================
// HELPER: MOCK MODULE RESOLUTION
// ============================================================================

/**
 * Setup default module mocks before tests run
 * Call this in beforeEach or beforeAll
 */
export const setupDefaultMocks = () => {
  // Mock Prisma
  jest.mock('../../src/prisma-wrapper', () => ({
    getPrisma: () => createMockPrisma(),
  }));

  // Mock fs
  jest.mock('fs', () => createMockFS());

  // Mock crypto
  jest.mock('crypto', () => createMockCrypto());
};

// ============================================================================
// HELPER: VERIFY MOCK CALLS
// ============================================================================

export const assertMockCalled = (mock: jest.Mock, times: number, message?: string) => {
  if (mock.mock.calls.length !== times) {
    throw new Error(
      `${message || 'Mock'} called ${mock.mock.calls.length} times, expected ${times}`
    );
  }
};

export const assertMockCalledWith = (mock: jest.Mock, expectedArgs: any[], message?: string) => {
  const found = mock.mock.calls.some((call) =>
    JSON.stringify(call) === JSON.stringify(expectedArgs)
  );
  if (!found) {
    throw new Error(`${message || 'Mock'} not called with expected arguments`);
  }
};

// ============================================================================
// TEST DATA FIXTURES
// ============================================================================

export const testFixtures = {
  validUser: {
    id: 'user-123',
    email: 'test@example.com',
    name: 'Test User',
    role: 'admin',
  },
  validCredential: {
    id: 'cred-123',
    name: 'Test Credential',
    type: 'password',
    value: 'SecurePassword123!@#',
    lastRotated: new Date('2026-03-10'),
    createdAt: new Date('2026-01-01'),
  },
  validPolicy: {
    id: 'policy-123',
    name: 'password_policy',
    rules: {
      minLength: 12,
      requireSpecialChars: true,
      requireNumbers: true,
    },
  },
  validAuditEntry: {
    id: 'audit-123',
    event: 'credential_rotated',
    resourceType: 'credential',
    resourceId: 'cred-123',
    actor: 'user-123',
    action: 'rotation',
    status: 'success' as const,
    timestamp: new Date(),
  },
};
