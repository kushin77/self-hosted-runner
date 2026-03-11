/**
 * Unit Tests: Authentication Service
 * Tests JWT token generation/verification, OAuth flows, and auth middleware
 */

import { describe, it, expect, beforeEach, afterEach, jest } from '@jest/globals';
import {
  generateToken,
  verifyToken,
  authenticationRequired,
  JWTPayload,
} from '../../../src/auth';
import { Request, Response, NextFunction } from 'express';

describe('Authentication Service', () => {
  describe('JWT Token Generation', () => {
    it('should generate valid JWT token', () => {
      const token = generateToken('user123', 'user@example.com', 'admin');

      expect(token).toBeDefined();
      expect(typeof token).toBe('string');
      expect(token.split('.')).toHaveLength(3); // JWT format: header.payload.signature
    });

    it('should generate different tokens for different users', () => {
      const token1 = generateToken('user1', 'user1@example.com', 'admin');
      const token2 = generateToken('user2', 'user2@example.com', 'viewer');

      expect(token1).not.toBe(token2);
    });

    it('should include timestamp in JWT payload (iat claim)', () => {
      const token1 = generateToken('user123', 'user@example.com', 'admin');
      const payload1 = verifyToken(token1);

      expect(payload1?.iat).toBeDefined();
      expect(typeof payload1?.iat).toBe('number');
    });
  });

  describe('JWT Token Verification', () => {
    let validToken: string;
    let userId: string;
    let userEmail: string;
    let userRole: string;

    beforeEach(() => {
      userId = 'user-' + Math.random().toString(36).substring(7);
      userEmail = `user-${Math.random()}@example.com`;
      userRole = 'admin';
      validToken = generateToken(userId, userEmail, userRole);
    });

    it('should verify valid JWT token (idempotent)', () => {
      const payload1 = verifyToken(validToken);
      const payload2 = verifyToken(validToken);

      expect(payload1).not.toBeNull();
      expect(payload2).not.toBeNull();
      expect(payload1?.userId).toBe(userId);
      expect(payload2?.userId).toBe(userId);
    });

    it('should extract correct claims from token', () => {
      const payload = verifyToken(validToken) as JWTPayload;

      expect(payload.userId).toBe(userId);
      expect(payload.email).toBe(userEmail);
      expect(payload.role).toBe(userRole);
    });

    it('should return null for invalid token', () => {
      const invalidToken = 'invalid.token.here';
      const payload = verifyToken(invalidToken);

      expect(payload).toBeNull();
    });

    it('should return null for malformed token', () => {
      const malformedToken = 'not-a-jwt';
      const payload = verifyToken(malformedToken);

      expect(payload).toBeNull();
    });

    it('should return null for tampered token (signature invalid)', () => {
      const [header, payload, signature] = validToken.split('.');
      const tamperedToken = `${header}.${payload}.invalidsignature`;
      const result = verifyToken(tamperedToken);

      expect(result).toBeNull();
    });

    it('should have exp claim for token expiration', () => {
      const payload = verifyToken(validToken) as JWTPayload;

      expect(payload.exp).toBeDefined();
      expect(typeof payload.exp).toBe('number');
      expect(payload.exp).toBeGreaterThan(Math.floor(Date.now() / 1000)); // Future time
    });

    it('should have iat claim for issued-at time', () => {
      const payload = verifyToken(validToken) as JWTPayload;

      expect(payload.iat).toBeDefined();
      expect(typeof payload.iat).toBe('number');
      expect(payload.iat).toBeLessThanOrEqual(Math.floor(Date.now() / 1000)); // Past or present
    });
  });

  describe('Authentication Middleware', () => {
    let req: Partial<Request>;
    let res: any;
    let next: NextFunction;

    beforeEach(() => {
      req = {
        headers: {},
      };
      res = {
        status: jest.fn(function() { return this; }),
        json: jest.fn(function() { return this; }),
        end: jest.fn(function() { return this; }),
        send: jest.fn(function() { return this; }),
        setHeader: jest.fn(function() { return this; }),
      };
      next = jest.fn();
    });

    it('should call next() when Authorization header is valid', () => {
      const token = generateToken('user123', 'user@example.com', 'admin');
      req.headers = { authorization: `Bearer ${token}` };

      authenticationRequired(req as any, res as any, next);

      expect(next).toHaveBeenCalled();
    });

    it('should return 401 when Authorization header is missing', () => {
      authenticationRequired(req as any, res as any, next);

      expect(res.status).toHaveBeenCalledWith(401);
      expect(res.json).toHaveBeenCalledWith(
        expect.objectContaining({
          error: 'Unauthorized',
        })
      );
      expect(next).not.toHaveBeenCalled();
    });

    it('should return 401 when Authorization header does not start with Bearer', () => {
      req.headers = { authorization: 'Basic user:pass' };

      authenticationRequired(req as any, res as any, next);

      expect(res.status).toHaveBeenCalledWith(401);
      expect(next).not.toHaveBeenCalled();
    });

    it('should return 401 when Bearer token is missing', () => {
      req.headers = { authorization: 'Bearer ' };

      authenticationRequired(req as any, res as any, next);

      expect(res.status).toHaveBeenCalledWith(401);
    });

    it('should return 401 when token is invalid', () => {
      req.headers = { authorization: 'Bearer invalid.token.here' };

      authenticationRequired(req as any, res as any, next);

      expect(res.status).toHaveBeenCalledWith(401);
      expect(next).not.toHaveBeenCalled();
    });

    it('should handle Authorization header case-insensitivity', () => {
      const token = generateToken('user123', 'user@example.com', 'admin');
      req.headers = {
        // Headers are case-insensitive in HTTP, express lowercases them
        authorization: `Bearer ${token}`,
      };

      authenticationRequired(req as any, res as any, next);

      expect(next).toHaveBeenCalled();
    });
  });

  describe('Token Security', () => {
    it('should not leak sensitive data in JWT payload', () => {
      // JWT is not encrypted, just signed. Make sure we don't put passwords in payload
      const token = generateToken('user123', 'user@example.com', 'admin');
      const [, payload] = token.split('.');

      // Decode base64 payload
      const decoded = Buffer.from(payload, 'base64').toString('utf-8');
      const claims = JSON.parse(decoded);

      // Verify no sensitive fields are present
      expect(decoded).not.toContain('password');
      expect(decoded).not.toContain('secret');
      expect(decoded).not.toContain('key');
      expect(decoded).not.toContain('token');
    });

    it('should have issuer claim set to nexusshield', () => {
      const token = generateToken('user123', 'user@example.com', 'admin');
      const payload = verifyToken(token) as JWTPayload & { iss: string };

      expect(payload.iss).toBe('nexusshield-portal');
    });

    it('should have audience claim set to API', () => {
      const token = generateToken('user123', 'user@example.com', 'admin');
      const payload = verifyToken(token) as JWTPayload & { aud: string };

      expect(payload.aud).toBe('nexusshield-api');
    });
  });

  describe('Token Idempotency', () => {
    it('should verify same token consistently (idempotent)', () => {
      const token = generateToken('user123', 'user@example.com', 'admin');

      // Verify same token 5 times
      const results = [
        verifyToken(token),
        verifyToken(token),
        verifyToken(token),
        verifyToken(token),
        verifyToken(token),
      ];

      // All results should be identical
      expect(results[0]?.userId).toBe('user123');
      expect(results[1]?.userId).toBe('user123');
      expect(results[2]?.userId).toBe('user123');
      expect(results[3]?.userId).toBe('user123');
      expect(results[4]?.userId).toBe('user123');

      // Results should match
      for (let i = 1; i < results.length; i++) {
        expect(results[i]?.userId).toBe(results[0]?.userId);
        expect(results[i]?.email).toBe(results[0]?.email);
        expect(results[i]?.role).toBe(results[0]?.role);
      }
    });
  });
});
