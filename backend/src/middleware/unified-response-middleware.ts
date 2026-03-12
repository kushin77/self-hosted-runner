/**
 * Middleware to enforce unified API response schema
 * 
 * Wraps Express res.json() to automatically apply APIResponse<T> envelope
 * Adds request tracking, error handling, and rate limiting headers
 */

import { Express, Request, Response, NextFunction } from 'express';
import crypto from 'crypto';
import {
  APIResponse,
  successResponse,
  errorResponse,
  ErrorCode,
  ErrorPayload,
  HttpStatus,
  getHttpStatus,
} from '../lib/unified-response';

declare global {
  namespace Express {
    interface Request {
      requestId: string;
      startTime: number;
    }
  }
}

/**
 * Rate limiting store (in production, use Redis)
 */
interface RateLimitBucket {
  count: number;
  resetAt: number;
}

const rateLimitStore = new Map<string, RateLimitBucket>();

/**
 * Middleware 1: Attach request ID and start time
 */
export function requestIdMiddleware(
  req: Request,
  res: Response,
  next: NextFunction
): void {
  req.requestId = crypto.randomUUID();
  req.startTime = Date.now();
  res.setHeader('X-Request-ID', req.requestId);
  next();
}

/**
 * Middleware 2: Enforce unified response format
 */
export function unifiedResponseMiddleware(
  req: Request,
  res: Response,
  next: NextFunction
): void {
  // Store original json method
  const originalJson = res.json.bind(res);

  // Override json to ensure APIResponse format
  res.json = function (data: any) {
    // If response is already APIResponse<T>, send as-is
    if (data && typeof data === 'object' && 'status' in data && 'metadata' in data) {
      res.setHeader('Content-Type', 'application/json');
      return originalJson(data);
    }

    // Otherwise wrap in success response
    const response = successResponse(data, req.requestId);
    res.setHeader('Content-Type', 'application/json');
    return originalJson(response);
  };

  next();
}

/**
 * Middleware 3: Rate limiting (1000 req/min per API key)
 */
export function rateLimitMiddleware(
  req: Request,
  res: Response,
  next: NextFunction
): void {
  // Get API key from header
  const apiKey = req.headers['x-api-key'] as string || 'anonymous';

  // Limit: 1000 requests per 60 seconds
  const LIMIT = 1000;
  const WINDOW = 60 * 1000; // 60 seconds

  // Check if bucket exists
  let bucket = rateLimitStore.get(apiKey);

  // Create or reset bucket if expired
  if (!bucket || bucket.resetAt < Date.now()) {
    bucket = {
      count: 0,
      resetAt: Date.now() + WINDOW,
    };
    rateLimitStore.set(apiKey, bucket);
  }

  // Increment counter
  bucket.count++;

  // Calculate remaining
  const remaining = Math.max(0, LIMIT - bucket.count);
  const resetIn = Math.ceil((bucket.resetAt - Date.now()) / 1000);

  // Set headers
  res.setHeader('X-RateLimit-Limit', LIMIT);
  res.setHeader('X-RateLimit-Remaining', remaining);
  res.setHeader('X-RateLimit-Reset', Math.ceil(bucket.resetAt / 1000));

  // Check if limit exceeded
  if (bucket.count > LIMIT) {
    res.setHeader('X-RateLimit-RetryAfter', resetIn);
    res.status(HttpStatus.TOO_MANY_REQUESTS).json(
      errorResponse(
        ErrorCode.RATE_LIMITED,
        `Rate limit exceeded: ${LIMIT} requests per ${WINDOW / 1000}s`,
        req.requestId,
        {
          retryable: true,
          retryAfter: resetIn * 1000,
          details: {
            limit: LIMIT,
            window: `${WINDOW / 1000}s`,
            retryAfterSeconds: resetIn,
          },
        }
      )
    );
    return;
  }

  next();
}

/**
 * Middleware 4: Response timing and logging
 */
export function responseTimingMiddleware(
  req: Request,
  res: Response,
  next: NextFunction
): void {
  // Intercept res.send to measure latency
  const originalJson = res.json.bind(res);

  res.json = function (data: any) {
    const latency = Date.now() - req.startTime;
    res.setHeader('X-Response-Time-MS', latency);

    // Log to console in development
    if (process.env.NODE_ENV !== 'production') {
      console.log(`[${req.method}] ${req.path} - ${res.statusCode} (${latency}ms)`);
    }

    return originalJson(data);
  };

  next();
}

/**
 * Error response middleware (should be last)
 */
export function errorHandlerMiddleware(
  err: any,
  req: Request,
  res: Response,
  next: NextFunction
): void {
  // Default error values
  let statusCode = HttpStatus.INTERNAL_SERVER_ERROR;
  let errorCode = ErrorCode.INTERNAL_ERROR;
  let message = 'An unexpected error occurred';
  let details: Record<string, any> | undefined;
  let retryable = false;

  // Handle known error types
  if (err.name === 'ValidationError') {
    statusCode = HttpStatus.BAD_REQUEST;
    errorCode = ErrorCode.INVALID_REQUEST;
    message = err.message;
    details = { validation: err.details };
  } else if (err.name === 'AuthenticationError') {
    statusCode = HttpStatus.UNAUTHORIZED;
    errorCode = ErrorCode.INVALID_TOKEN;
    message = err.message;
  } else if (err.name === 'AuthorizationError') {
    statusCode = HttpStatus.FORBIDDEN;
    errorCode = ErrorCode.PERMISSION_DENIED;
    message = err.message;
  } else if (err.status) {
    statusCode = err.status;
    errorCode = err.code || ErrorCode.INTERNAL_ERROR;
    message = err.message;
    retryable = err.retryable ?? false;
  }

  // Log error
  console.error({
    requestId: req.requestId,
    error: err.message,
    stack: process.env.NODE_ENV === 'development' ? err.stack : undefined,
  });

  res.status(statusCode).json(
    errorResponse(errorCode, message, req.requestId, {
      retryable,
      details,
    })
  );
}

/**
 * Register all unified response middleware with Express app
 */
export function setupUnifiedResponseMiddleware(app: Express): void {
  // Order matters: request ID → response wrapping → rate limiting → timing
  app.use(requestIdMiddleware);
  app.use(unifiedResponseMiddleware);
  app.use(rateLimitMiddleware);
  app.use(responseTimingMiddleware);
}

/**
 * Register error handler (should be last)
 */
export function setupErrorHandling(app: Express): void {
  // Must be last middleware
  app.use(errorHandlerMiddleware);
}
