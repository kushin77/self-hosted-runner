/**
 * Jest Mock Utilities
 * Provides mock implementations for external services (Prisma, GCP, Vault, KMS)
 */

import { jest } from '@jest/globals';

// ============================================================================
// PRISMA MOCK
// ============================================================================

export const createMockPrisma = () => ({
  auditLog: {
    create: jest.fn().mockResolvedValue({
      id: 'audit-1',
      created_at: new Date(),
      event: 'test_event',
      resource_type: 'test',
      actor_id: 'test_user',
      action: 'test',
      hash: 'abc123',
      previous_hash: 'prev123',
    }),
    findFirst: jest.fn().mockResolvedValue({
      id: 'audit-1',
      hash: 'abc123',
      created_at: new Date(),
    }),
    findMany: jest.fn().mockResolvedValue([]),
  },
  credentialPolicy: {
    findMany: jest.fn().mockResolvedValue([]),
    findUnique: jest.fn().mockResolvedValue(null),
    create: jest.fn().mockResolvedValue({
      id: 'policy-1',
      name: 'test_policy',
      rules: {},
    }),
  },
  credential: {
    findUnique: jest.fn().mockResolvedValue({
      id: 'cred-1',
      name: 'test_cred',
      type: 'password',
    }),
    findMany: jest.fn().mockResolvedValue([]),
    create: jest.fn().mockResolvedValue({
      id: 'cred-1',
      name: 'test_cred',
      type: 'password',
    }),
    update: jest.fn().mockResolvedValue({
      id: 'cred-1',
      name: 'test_cred',
      type: 'password',
    }),
  },
  $executeRaw: jest.fn().mockResolvedValue(undefined),
  $queryRaw: jest.fn().mockResolvedValue([]),
});

// ============================================================================
// GCP SECRET MANAGER MOCK
// ============================================================================

export const createMockSecretManager = () => {
  const mockClient = jest.mocked({
    accessSecret: jest.fn().mockResolvedValue({
      payload: { data: Buffer.from('test-secret-value') },
    }),
    getSecret: jest.fn().mockResolvedValue({ name: 'test-secret' }),
    addSecretVersion: jest.fn().mockResolvedValue({ name: 'test-version' }),
    createSecret: jest.fn().mockResolvedValue({ name: 'test-secret' }),
  });
  return mockClient;
};

// ============================================================================
// VAULT MOCK
// ============================================================================

export const createMockVault = () => {
  const mockVault = {
    read: jest
      .fn()
      .mockResolvedValue({ data: { data: { value: 'vault-secret-value' } } }),
    write: jest
      .fn()
      .mockResolvedValue({ data: { data: { version: 1 } } }),
    destroy: jest.fn().mockResolvedValue({}),
  };
  return mockVault;
};

// ============================================================================
// KMS MOCK
// ============================================================================

export const createMockKMS = () => {
  const mockKMS = {
    decrypt: jest.fn().mockResolvedValue({
      plaintext: Buffer.from('decrypted-value'),
    }),
    encrypt: jest.fn().mockResolvedValue({
      ciphertext: Buffer.from('encrypted-value'),
    }),
  };
  return mockKMS;
};

// ============================================================================
// JWT MOCK
// ============================================================================

export const createMockJWT = () => ({
  sign: jest.fn().mockReturnValue('mock-jwt-token'),
  verify: jest.fn().mockReturnValue({
    userId: 'test-user',
    email: 'test@example.com',
    role: 'admin',
    iat: Math.floor(Date.now() / 1000),
    exp: Math.floor(Date.now() / 1000) + 86400,
  }),
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
  readFileSync: jest
    .fn()
    .mockReturnValue('{"id":"abc123","hash":"def456"}'),
  writeFileSync: jest.fn().mockReturnValue(undefined),
  appendFileSync: jest.fn().mockReturnValue(undefined),
  existsSync: jest.fn().mockReturnValue(true),
  mkdirSync: jest.fn().mockReturnValue(undefined),
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
  get: jest.fn().mockResolvedValue(null),
  set: jest.fn().mockResolvedValue('OK'),
  del: jest.fn().mockResolvedValue(1),
  exists: jest.fn().mockResolvedValue(0),
  expire: jest.fn().mockResolvedValue(1),
  ttl: jest.fn().mockResolvedValue(-1),
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
    name: 'db_password',
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
    resourceId: 'db_password',
    actor: 'user-123',
    action: 'rotation',
    status: 'success' as const,
    timestamp: new Date(),
  },
};
