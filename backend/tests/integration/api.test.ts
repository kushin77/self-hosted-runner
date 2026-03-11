/**
 * Integration Tests: API Endpoints
 * Tests full HTTP request/response cycle with mocked external dependencies
 */

import { describe, it, expect, beforeEach, jest } from '@jest/globals';
import request from 'supertest';
import { Express } from 'express';

/**
 * Mock Express app for testing
 * In real scenario, this would import the actual Express app
 */
function createTestApp(): Express {
  const express = require('express');
  const app = express();

  app.use(express.json());

  // Health check endpoint
  app.get('/health', (req, res) => {
    res.status(200).json({
      status: 'healthy',
      timestamp: new Date().toISOString(),
      version: '1.0.0-alpha',
      checks: {
        database: 'ok',
        vault: 'ok',
        gsm: 'ok',
      },
    });
  });

  // Login endpoint
  app.post('/auth/login', (req, res) => {
    const { email, password } = req.body;

    if (!email || !password) {
      return res.status(400).json({
        code: 'VALIDATION_FAILED',
        message: 'Email and password required',
      });
    }

    if (email === 'user@example.com' && password === 'correct-password') {
      return res.status(200).json({
        token: 'jwt-token-here',
        expiresIn: 3600,
      });
    }

    return res.status(401).json({
      code: 'AUTH_FAILED',
      message: 'Invalid credentials',
    });
  });

  // Status endpoint
  app.get('/api/v1/status', (req, res) => {
    res.status(200).json({
      service: 'nexusshield-portal-backend',
      status: 'operational',
      uptime_ms: 12345,
    });
  });

  // Error handling middleware
  app.use((err: any, req: any, res: any, next: any) => {
    res.status(err.statusCode || 500).json({
      code: err.code || 'INTERNAL_SERVER_ERROR',
      message: err.message,
      timestamp: new Date().toISOString(),
    });
  });

  return app;
}

describe('API Integration Tests', () => {
  let app: Express;

  beforeEach(() => {
    app = createTestApp();
  });

  describe('GET /health', () => {
    it('should return 200 OK with health status', async () => {
      const response = await request(app)
        .get('/health')
        .expect(200);

      expect(response.body.status).toBe('healthy');
      expect(response.body.timestamp).toBeDefined();
      expect(response.body.version).toBeDefined();
    });

    it('should include dependency checks in health response', async () => {
      const response = await request(app)
        .get('/health')
        .expect(200);

      expect(response.body.checks).toHaveProperty('database');
      expect(response.body.checks).toHaveProperty('vault');
      expect(response.body.checks).toHaveProperty('gsm');
    });
  });

  describe('POST /auth/login', () => {
    it('should authenticate with valid credentials', async () => {
      const response = await request(app)
        .post('/auth/login')
        .send({
          email: 'user@example.com',
          password: 'correct-password',
        })
        .expect(200);

      expect(response.body.token).toBeDefined();
      expect(response.body.expiresIn).toBe(3600);
    });

    it('should reject invalid credentials', async () => {
      const response = await request(app)
        .post('/auth/login')
        .send({
          email: 'user@example.com',
          password: 'wrong-password',
        })
        .expect(401);

      expect(response.body.code).toBe('AUTH_FAILED');
    });

    it('should require email and password', async () => {
      const response = await request(app)
        .post('/auth/login')
        .send({
          email: 'user@example.com',
        })
        .expect(400);

      expect(response.body.code).toBe('VALIDATION_FAILED');
    });
  });

  describe('GET /api/v1/status', () => {
    it('should return service status', async () => {
      const response = await request(app)
        .get('/api/v1/status')
        .expect(200);

      expect(response.body.service).toBe('nexusshield-portal-backend');
      expect(response.body.status).toBe('operational');
      expect(response.body.uptime_ms).toBeGreaterThanOrEqual(0);
    });
  });

  describe('Error Handling', () => {
    it('should return consistent error format', async () => {
      const response = await request(app)
        .post('/auth/login')
        .send({})
        .expect(400);

      expect(response.body).toHaveProperty('code');
      expect(response.body).toHaveProperty('message');
      expect(response.body).toHaveProperty('timestamp');
    });
  });
});
