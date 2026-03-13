/**
 * Test Fixtures
 * Real test data for use with actual configurations
 */

export const testCredentials = {
  gsm: {
    name: 'test-gsm-secret',
    value: 'gsm-secret-value-12345',
    type: 'gsm' as const,
  },
  vault: {
    name: 'test-vault-secret',
    value: 'vault-secret-value-67890',
    type: 'vault' as const,
  },
  kms: {
    name: 'test-kms-key',
    value: 'kms-encrypted-value-abcde',
    type: 'kms' as const,
  },
};

export const testUsers = {
  admin: {
    id: 'user-admin-001',
    email: 'admin@test.com',
    name: 'Test Admin',
    role: 'admin',
  },
  operator: {
    id: 'user-operator-001',
    email: 'operator@test.com',
    name: 'Test Operator',
    role: 'operator',
  },
  viewer: {
    id: 'user-viewer-001',
    email: 'viewer@test.com',
    name: 'Test Viewer',
    role: 'viewer',
  },
};

export const testPolicies = {
  passwordPolicy: {
    name: 'password-policy',
    rules: {
      minLength: 12,
      requireSpecialChars: true,
      requireNumbers: true,
      requireUppercase: true,
      maxLifetime: 90,
    },
    resourceTypes: ['gsm', 'vault', 'kms'],
    resourceNames: ['prod-*', 'staging-*'],
    enabled: true,
    enforced: true,
  },
  apiKeyPolicy: {
    name: 'api-key-policy',
    rules: {
      minLength: 32,
      requireSpecialChars: false,
      requireNumbers: true,
      maxLifetime: 365,
    },
    resourceTypes: ['gsm'],
    resourceNames: ['api-key-*'],
    enabled: true,
    enforced: false,
  },
};

export const testAuditEvents = {
  credentialCreated: {
    event: 'credential_created' as const,
    resourceType: 'credential' as const,
    resourceId: 'cred-001',
    actor: 'user-admin-001',
    action: 'create',
    status: 'success' as const,
    details: { name: 'test-secret', type: 'gsm' },
  },
  credentialRotated: {
    event: 'credential_rotated' as const,
    resourceType: 'credential' as const,
    resourceId: 'cred-001',
    actor: 'system',
    action: 'rotate',
    status: 'success' as const,
    details: { reason: 'scheduled' },
  },
  accessDenied: {
    event: 'access_denied' as const,
    resourceType: 'credential' as const,
    resourceId: 'cred-restricted',
    actor: 'user-viewer-001',
    action: 'read',
    status: 'denied' as const,
    details: { reason: 'insufficient permissions' },
  },
};

export const testApiEndpoints = {
  health: {
    method: 'GET' as const,
    path: '/health',
    expectedStatus: 200,
  },
  authLogin: {
    method: 'POST' as const,
    path: '/auth/login',
    body: { email: 'admin@test.com', password: 'TestPassword123!' },
    expectedStatus: 200,
  },
  credentialsList: {
    method: 'GET' as const,
    path: '/api/v1/credentials',
    expectedStatus: 200,
  },
  credentialsGet: {
    method: 'GET' as const,
    path: '/api/v1/credentials/test-secret',
    expectedStatus: 200,
  },
  auditQuery: {
    method: 'GET' as const,
    path: '/api/v1/audit?limit=10',
    expectedStatus: 200,
  },
};

export const testComplianceViolations = {
  shortPassword: {
    credentialName: 'weak-password',
    credentialType: 'gsm',
    value: 'short',
    expectedViolations: ['minLength'],
  },
  noSpecialChars: {
    credentialName: 'nopunct-password',
    credentialType: 'gsm',
    value: 'Password12345',
    expectedViolations: ['requireSpecialChars'],
  },
  expiredCredential: {
    credentialName: 'old-credential',
    credentialType: 'gsm',
    lastRotated: new Date(Date.now() - 100 * 24 * 60 * 60 * 1000), // 100 days ago
    expectedViolations: ['maxLifetime'],
  },
};
