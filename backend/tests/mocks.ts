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
      count: jest.fn(async (_opts?: any) => auditLogCounter),
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
      upsert: jest.fn(async (input: any) => {
        const data = input.create || input.update || {};
        return {
          id: data.id || 'policy-1',
          name: data.name || 'test_policy',
          description: data.description || null,
          rules: typeof data.rules === 'string' ? data.rules : JSON.stringify(data.rules || {}),
          resource_types: data.resourceTypes || data.resource_types || [],
          resource_names: data.resource_names || data.resourceNames || [],
          resourceNames: data.resourceNames || data.resource_names || [],
          enabled: typeof data.enabled === 'boolean' ? data.enabled : true,
          enforced: typeof data.enforced === 'boolean' ? data.enforced : false,
          created_at: data.created_at || new Date(),
          updated_at: data.updated_at || new Date(),
        };
      }),
    },
    credential: {
      findUnique: jest.fn(async () => ({
        id: 'cred-1',
        name: 'test_cred',
        type: 'password',
        created_at: new Date(Date.now() - 30 * 24 * 60 * 60 * 1000),
        rotations: [{ rotated_at: new Date(Date.now() - 10 * 24 * 60 * 60 * 1000) }],
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
      upsert: jest.fn(async (input: any) => {
        const data = input.create || input.update || input.data || {};
        return {
          id: data.id || input.where?.id || `cred-${++credentialCounter}`,
          name: data.name || 'test_cred',
          type: data.type || 'password',
          value: data.value,
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
    scheduledRotation: {
      upsert: jest.fn(async (input: any) => {
        const data = input.create || input.update || {};
        return {
          id: data.id || 'sched-1',
          credentialId: data.credentialId || null,
          nextRunAt: data.nextRunAt || new Date(),
        };
      }),
      findMany: jest.fn(async () => []),
    },
    rotationHistory: {
      create: jest.fn(async (input: any) => {
        const data = input.data || input.create || {};
        return {
          id: data.id || `rot-${Date.now()}`,
          credentialId: data.credentialId || data.credential_id || null,
          changeType: data.changeType || data.change_type || 'rotation',
          changedBy: data.changedBy || data.changed_by || 'system',
          details: data.details || null,
          created_at: data.created_at || new Date(),
        };
      }),
    },
    systemMetrics: {
      create: jest.fn(async (input: any) => {
        const data = input.data || {};
        return {
          id: data.id || `metric-${Date.now()}`,
          name: data.name || 'test_metric',
          value: data.value || 0,
          recorded_at: data.recorded_at || new Date(),
        };
      }),
      findMany: jest.fn(async (_opts?: any) => []),
    },
    complianceEvent: {
      create: jest.fn(async (input: any) => {
        const data = input.data || {};
        return {
          id: data.id || `ce-${Date.now()}`,
          event_type: data.event_type || 'policy_violation',
          resource_type: data.resource_type || 'credential',
          resource_id: data.resource_id || null,
          severity: data.severity || 'high',
          status: data.status || 'open',
          details: data.details || JSON.stringify({}),
          remediation: data.remediation || null,
          created_at: data.created_at || new Date(),
          resolved_at: data.resolved_at || null,
        };
      }),
      findMany: jest.fn(async (_opts?: any) => []),
    },
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
  createWriteStream: jest.fn(() => ({
    write: jest.fn(),
    end: jest.fn(),
    on: jest.fn(),
  })),
});

// ============================================================================
// CRYPTO MOCK
// ============================================================================

export const createMockCrypto = () => ({
  createHash: jest.fn().mockImplementation((algo) => {
    return {
      update: (input: any) => {
        const last = typeof input === 'string' ? input : JSON.stringify(input);
        return {
          digest: (_enc?: any) => `mock-hash-${Buffer.from(String(last)).toString('hex').slice(0,8)}-${Math.floor(Math.random()*100000)}`,
        };
      },
      digest: () => `mock-hash-${Math.floor(Math.random()*100000)}`,
    } as any;
  }),
  randomBytes: jest.fn().mockReturnValue(Buffer.from('randomness')),
  createHmac: jest.fn().mockImplementation(() => ({
    update: jest.fn().mockReturnThis(),
    digest: jest.fn().mockReturnValue('mock-hmac'),
  })),
  randomUUID: jest.fn(() => `mock-uuid-${Date.now()}`),
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
  jest.mock('../src/prisma-wrapper', () => ({
    getPrisma: () => createMockPrisma(),
  }));

  // Mock fs
  jest.mock('fs', () => createMockFS());

  // Mock crypto
  jest.mock('crypto', () => createMockCrypto());

  // Mock Google Secret Manager client
  jest.mock('@google-cloud/secret-manager', () => ({
    SecretManagerServiceClient: function () {
      return createMockSecretManager();
    },
  }));

  // Mock node-vault
  jest.mock('node-vault', () => {
    return jest.fn(() => createMockVault());
  });

  // Mock Google KMS
  jest.mock('@google-cloud/kms', () => ({
    KeyManagementServiceClient: function () {
      return createMockKMS();
    },
  }));
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
