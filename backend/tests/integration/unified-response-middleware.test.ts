import { Express, Response, Request, NextFunction } from 'express';
import request from 'supertest';
import express from 'express';
import {
  setupUnifiedResponseMiddleware,
  setupErrorHandling,
  requestIdMiddleware,
  unifiedResponseMiddleware,
  rateLimitMiddleware,
} from '../../src/middleware/unified-response-middleware';
import { ErrorCode, HttpStatus } from '../../src/lib/unified-response';

describe('Unified Response Middleware', () => {
  let app: Express;

  beforeEach(() => {
    app = express();
    app.use(express.json());
    
    // Register middleware
    setupUnifiedResponseMiddleware(app);

    // Test route: success
    app.get('/test/success', (req: Request, res: Response) => {
      res.json({ id: 1, name: 'test' });
    });

    // Test route: error
    app.get('/test/error', (req: Request, res: Response) => {
      const err = new Error('Test error');
      (err as any).status = HttpStatus.BAD_REQUEST;
      (err as any).code = ErrorCode.INVALID_REQUEST;
      throw err;
    });

    // Register error handler
    setupErrorHandling(app);
  });

  describe('Request ID Middleware', () => {
    it('should attach requestId to request object', async () => {
      const server = express();
      server.use(requestIdMiddleware);
      server.get('/test', (req: Request, res: Response) => {
        res.json({ requestId: req.requestId });
      });

      const response = await request(server).get('/test');
      expect(response.body.requestId).toBeDefined();
      expect(response.statusCode).toBe(200);
    });

    it('should set X-Request-ID header', async () => {
      const response = await request(app).get('/test/success');
      expect(response.headers['x-request-id']).toBeDefined();
    });
  });

  describe('Unified Response Middleware', () => {
    it('should wrap data in APIResponse on success', async () => {
      const response = await request(app).get('/test/success');

      expect(response.statusCode).toBe(200);
      expect(response.body.status).toBe('success');
      expect(response.body.data).toEqual({ id: 1, name: 'test' });
      expect(response.body.error).toBeNull();
      expect(response.body.metadata).toBeDefined();
      expect(response.body.metadata.requestId).toBeDefined();
      expect(response.body.metadata.timestamp).toBeDefined();
      expect(response.body.metadata.version).toBe('v1');
    });

    it('should preserve already-wrapped responses', async () => {
      app.get('/test/wrapped', (req: Request, res: Response) => {
        res.json({
          status: 'success',
          data: { id: 1 },
          error: null,
          metadata: {
            requestId: req.requestId,
            timestamp: new Date().toISOString(),
            version: 'v1',
          },
        });
      });

      const response = await request(app).get('/test/wrapped');
      expect(response.body.status).toBe('success');
      expect(response.body.metadata.requestId).toBeDefined();
    });
  });

  describe('Rate Limiting Middleware', () => {
    it('should set rate limit headers', async () => {
      const response = await request(app)
        .get('/test/success')
        .set('X-API-Key', 'test-key');

      expect(response.headers['x-ratelimit-limit']).toBeDefined();
      expect(response.headers['x-ratelimit-remaining']).toBeDefined();
      expect(response.headers['x-ratelimit-reset']).toBeDefined();
    });

    it('should block requests exceeding limit', async () => {
      const apiKey = 'test-limit-key';
      const limit = 1000;

      // Make 1001 requests
      for (let i = 0; i <= limit; i++) {
        const response = await request(app)
          .get('/test/success')
          .set('X-API-Key', apiKey);

        if (i === limit) {
          // 1001st request should be blocked
          expect(response.statusCode).toBe(HttpStatus.TOO_MANY_REQUESTS);
          expect(response.body.status).toBe('error');
          expect(response.body.error.code).toBe(ErrorCode.RATE_LIMITED);
          expect(response.body.error.retryable).toBe(true);
          expect(response.body.error.retryAfter).toBeDefined();
        }
      }
    });

    it('should track limits per API key', async () => {
      // Key 1: 5 requests
      for (let i = 0; i < 5; i++) {
        await request(app).get('/test/success').set('X-API-Key', 'key-1');
      }

      // Key 2: 3 requests
      for (let i = 0; i < 3; i++) {
        await request(app).get('/test/success').set('X-API-Key', 'key-2');
      }

      // Check remaining for each key
      const res1 = await request(app)
        .get('/test/success')
        .set('X-API-Key', 'key-1');
      const remaining1 = parseInt(res1.headers['x-ratelimit-remaining']);

      const res2 = await request(app)
        .get('/test/success')
        .set('X-API-Key', 'key-2');
      const remaining2 = parseInt(res2.headers['x-ratelimit-remaining']);

      // key-1 should have fewer remaining
      expect(remaining1).toBeLessThan(remaining2);
    });
  });

  describe('Error Handler Middleware', () => {
    it('should catch errors and return APIResponse with error status', async () => {
      app.get('/test/throws', (req: Request, res: Response) => {
        throw new Error('Test error');
      });

      const response = await request(app).get('/test/throws');
      expect(response.statusCode).toBe(HttpStatus.INTERNAL_SERVER_ERROR);
      expect(response.body.status).toBe('error');
      expect(response.body.error.code).toBe(ErrorCode.INTERNAL_ERROR);
      expect(response.body.data).toBeNull();
    });
  });

  describe('Content-Type Headers', () => {
    it('should set Content-Type to application/json', async () => {
      const response = await request(app).get('/test/success');
      expect(response.headers['content-type']).toContain('application/json');
    });
  });
});
