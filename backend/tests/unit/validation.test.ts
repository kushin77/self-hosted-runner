/**
 * Unit Tests: Input Validation
 * Tests Zod schema validation for all API request types
 */

import { describe, it, expect } from '@jest/globals';
import {
  LoginSchema,
  OAuthSchema,
  CredentialAccessSchema,
  CredentialCreateSchema,
  CredentialRotationSchema,
  AuditQuerySchema,
  validate,
  validateSafe,
} from '../../src/validation';
import { ZodError } from 'zod';

describe('Input Validation Schemas', () => {
  describe('LoginSchema', () => {
    it('should validate correct login request', () => {
      const validLogin = {
        email: 'user@example.com',
        password: 'SecurePass123!',
      };
      const result = LoginSchema.parse(validLogin);
      expect(result.email).toBe('user@example.com');
      expect(result.password).toBe('SecurePass123!');
    });

    it('should lowercase email addresses', () => {
      const result = LoginSchema.parse({
        email: 'User@EXAMPLE.COM',
        password: 'SecurePass123!',
      });
      expect(result.email).toBe('user@example.com');
    });

    it('should reject invalid email', () => {
      expect(() =>
        LoginSchema.parse({
          email: 'not-an-email',
          password: 'SecurePass123!',
        }),
      ).toThrow(ZodError);
    });

    it('should reject password shorter than 8 characters', () => {
      expect(() =>
        LoginSchema.parse({
          email: 'user@example.com',
          password: 'Short1!',
        }),
      ).toThrow(ZodError);
    });
  });

  describe('CredentialAccessSchema', () => {
    it('should validate credential name format', () => {
      const validNames = ['REDACTED', 'api-key-prod', 'secret.value'];
      validNames.forEach((name) => {
        const result = CredentialAccessSchema.parse({ name });
        expect(result.name).toBe(name);
      });
    });

    it('should reject invalid credential names', () => {
      const invalidNames = ['secret@name', 'secret name', ''];
      invalidNames.forEach((name) => {
        expect(() =>
          CredentialAccessSchema.parse({ name }),
        ).toThrow(ZodError);
      });
    });

    it('should enforce name length limits', () => {
      const tooLongName = 'a'.repeat(257);
      expect(() =>
        CredentialAccessSchema.parse({ name: tooLongName }),
      ).toThrow(ZodError);
    });
  });

  describe('CredentialCreateSchema', () => {
    it('should validate complete credential creation', () => {
      const validCreate = {
        name: 'new-secret',
        value: 'secret-value-here',
        type: 'api_key' as const,
        metadata: { environment: 'production' },
      };
      const result = CredentialCreateSchema.parse(validCreate);
      expect(result.name).toBe('new-secret');
      expect(result.type).toBe('api_key');
    });

    it('should reject invalid credential type', () => {
      expect(() =>
        CredentialCreateSchema.parse({
          name: 'new-secret',
          value: 'secret-value',
          type: 'invalid-type',
        }),
      ).toThrow(ZodError);
    });

    it('should require credential value', () => {
      expect(() =>
        CredentialCreateSchema.parse({
          name: 'new-secret',
          value: '',
          type: 'password',
        }),
      ).toThrow(ZodError);
    });

    it('should make metadata optional', () => {
      const result = CredentialCreateSchema.parse({
        name: 'new-secret',
        value: 'secret-value',
        type: 'token',
      });
      expect(result.metadata).toBeUndefined();
    });
  });

  describe('AuditQuerySchema', () => {
    it('should validate audit query with defaults', () => {
      const result = AuditQuerySchema.parse({});
      expect(result.limit).toBe(100);
      expect(result.offset).toBe(0);
    });

    it('should respect custom pagination limits', () => {
      const result = AuditQuerySchema.parse({
        limit: 50,
        offset: 100,
      });
      expect(result.limit).toBe(50);
      expect(result.offset).toBe(100);
    });

    it('should reject limit over 1000', () => {
      expect(() =>
        AuditQuerySchema.parse({ limit: 1001 }),
      ).toThrow(ZodError);
    });

    it('should allow filtering by action', () => {
      const result = AuditQuerySchema.parse({
        action: 'rotated',
      });
      expect(result.action).toBe('rotated');
    });
  });

  describe('validateSafe function', () => {
    it('should return null on validation error instead of throwing', () => {
      const result = validateSafe(LoginSchema, {
        email: 'invalid-email',
        password: 'short',
      });
      expect(result).toBeNull();
    });

    it('should return validated data on success', () => {
      const result = validateSafe(LoginSchema, {
        email: 'user@example.com',
        password: 'ValidPass123!',
      });
      expect(result).not.toBeNull();
      expect(result?.email).toBe('user@example.com');
    });
  });

  describe('OAuthSchema', () => {
    it('should validate OAuth parameters', () => {
      const result = OAuthSchema.parse({
        provider: 'github',
        code: 'auth-code-123',
        redirectUri: 'https://myapp.com/callback',
      });
      expect(result.provider).toBe('github');
    });

    it('should reject invalid provider', () => {
      expect(() =>
        OAuthSchema.parse({
          provider: 'twitter',
          code: 'auth-code',
          redirectUri: 'https://myapp.com/callback',
        }),
      ).toThrow(ZodError);
    });

    it('should validate redirect URI format', () => {
      expect(() =>
        OAuthSchema.parse({
          provider: 'google',
          code: 'auth-code',
          redirectUri: 'not-a-url',
        }),
      ).toThrow(ZodError);
    });
  });
});
