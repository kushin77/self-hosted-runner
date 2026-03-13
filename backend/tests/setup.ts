/**
 * Jest Test Setup
 * Runs before each test suite to configure global test utilities
 */

import { TextEncoder, TextDecoder } from 'util';
import { jest, expect, beforeAll, afterEach } from '@jest/globals';
import * as path from 'path';

// Polyfills for Node.js
global.TextEncoder = TextEncoder;
global.TextDecoder = TextDecoder as any;

/**
 * Load test environment configuration
 */
const testEnvPath = path.join(__dirname, 'config', 'test.env');
try {
  require('dotenv').config({ path: testEnvPath });
} catch (e) {
  // dotenv not available, continue with process.env
}

/**
 * Mock Prisma wrapper globally
 */
jest.mock('./src/prisma-wrapper', () => {
  const mocks = require('./mocks');
  return {
    getPrisma: () => mocks.createMockPrisma(),
  };
});

/**
 * Mock environment variables for testing
 */
beforeAll(() => {
  process.env.NODE_ENV = 'test';
  process.env.DATABASE_URL = 'postgresql://test:test@localhost:5432/test';
  process.env.VAULT_ADDR = 'http://localhost:8200';
  process.env.VAULT_TKN = 'test-token';
  process.env.GCP_PROJECT = 'test-project';
  process.env.JWT_SECRET = 'test-secret-key-min-32-chars-long';
  process.env.CORS_ORIGINS = 'http://localhost:3001';
});

/**
 * Clean up after each test
 */
afterEach(() => {
  jest.clearAllMocks();
});

/**
 * Custom jest matchers can be added here
 */
expect.extend({
  toBeValidUUID(received: string) {
    const uuidRegex =
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    const pass = uuidRegex.test(received);
    return {
      pass,
      message: () =>
        `expected ${received} to be a valid UUID`,
    };
  },
});
