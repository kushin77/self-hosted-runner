/**
 * Unified API Response Layer
 * 
 * All endpoints return a consistent APIResponse<T> envelope with:
 * - status: 'success' | 'error' | 'partial'
 * - data: T | null
 * - error: ErrorPayload | null
 * - metadata: ResponseMetadata
 * 
 * This ensures:
 * 1. Client SDK consistency (TypeScript, Python, Go)
 * 2. Predictable error handling (code + retryable flag)
 * 3. Request tracing (requestId in every response)
 * 4. Rate limiting info (retryAfter for client backoff)
 */

/**
 * HTTP Status Code enum for standardized response codes
 */
export enum HttpStatus {
  // 2xx Success
  OK = 200,
  CREATED = 201,
  ACCEPTED = 202,
  NO_CONTENT = 204,

  // 4xx Client Error
  BAD_REQUEST = 400,
  UNAUTHORIZED = 401,
  FORBIDDEN = 403,
  NOT_FOUND = 404,
  CONFLICT = 409,
  TOO_MANY_REQUESTS = 429,

  // 5xx Server Error
  INTERNAL_SERVER_ERROR = 500,
  SERVICE_UNAVAILABLE = 503,
  GATEWAY_TIMEOUT = 504,
}

/**
 * Standard Error Codes used across all endpoints
 * Format: {category}/{specific-error}
 */
export enum ErrorCode {
  // Authentication (auth/*)
  INVALID_TOKEN = 'auth/invalid-token',
  TOKEN_EXPIRED = 'auth/token-expired',
  PERMISSION_DENIED = 'auth/permission-denied',
  MISSING_CREDENTIALS = 'auth/missing-credentials',

  // Credential Management (credential/*)
  ROTATION_FAILED = 'credential/rotation-failed',
  NOT_FOUND = 'credential/not-found',
  QUOTA_EXHAUSTED = 'credential/quota-exhausted',
  INVALID_TYPE = 'credential/invalid-type',

  // Validation (validation/*)
  INVALID_REQUEST = 'validation/invalid-request',
  MISSING_REQUIRED_FIELD = 'validation/missing-required-field',
  INVALID_FORMAT = 'validation/invalid-format',

  // Server (server/*)
  INTERNAL_ERROR = 'server/internal-error',
  UNAVAILABLE = 'server/unavailable',
  RATE_LIMITED = 'server/rate-limited',
  GATEWAY_TIMEOUT = 'server/gateway-timeout',
}

/**
 * Error Payload returned in APIResponse.error
 */
export interface ErrorPayload {
  /** Standard error code (e.g., 'auth/invalid-token') */
  code: ErrorCode | string;

  /** Human-readable error message */
  message: string;

  /** Additional context for debugging */
  details?: Record<string, any>;

  /** Whether client should retry this request */
  retryable: boolean;

  /** If retryable, milliseconds to wait before retry */
  retryAfter?: number;
}

/**
 * Response Metadata included in every response
 */
export interface ResponseMetadata {
  /** Unique request identifier for tracing */
  requestId: string;

  /** ISO 8601 timestamp when response was generated */
  timestamp: string;

  /** API version (e.g., 'v1') */
  version: string;

  /** Non-critical warnings (e.g., deprecated fields) */
  warnings?: string[];
}

/**
 * Unified API Response envelope
 * 
 * Generic type T allows type-safe access to response data
 * 
 * @example
 * interface CredentialResponse {
 *   credentialId: string;
 *   type: 'aws_sts' | 'gsm' | 'vault' | 'kms';
 *   expiresAt: string;
 *   rotatedAt: string;
 * }
 * 
 * const response: APIResponse<CredentialResponse> = {
 *   status: 'success',
 *   data: {...},
 *   error: null,
 *   metadata: {...}
 * }
 */
export interface APIResponse<T = any> {
  /** Success status: 'success' | 'error' | 'partial' */
  status: 'success' | 'error' | 'partial';

  /** Response data (null if error or no data) */
  data: T | null;

  /** Error details (null if success) */
  error: ErrorPayload | null;

  /** Metadata (always present) */
  metadata: ResponseMetadata;
}

/**
 * Request context attached to Express Request object
 */
export interface RequestContext {
  /** Unique request identifier */
  requestId: string;

  /** Authenticated user ID (if applicable) */
  userId?: string;

  /** Request start time (for latency calculation) */
  startTime: number;
}

/**
 * Helper to create success response
 * 
 * @param data - Response payload
 * @param requestId - Request ID for tracing
 * @param status - HTTP status code (defaults to 200)
 * @returns APIResponse<T>
 * 
 * @example
 * const cred = await credentialService.get(id);
 * return res.status(200).json(successResponse(cred, requestId));
 */
export function successResponse<T>(
  data: T,
  requestId: string,
  status: HttpStatus = HttpStatus.OK
): APIResponse<T> {
  return {
    status: 'success',
    data,
    error: null,
    metadata: {
      requestId,
      timestamp: new Date().toISOString(),
      version: 'v1',
    },
  };
}

/**
 * Helper to create error response
 * 
 * @param code - Error code (from ErrorCode enum)
 * @param message - Human-readable message
 * @param requestId - Request ID for tracing
 * @param options - Additional options (retryable, retryAfter, details)
 * @returns APIResponse<null>
 * 
 * @example
 * if (!token) {
 *   return res.status(401).json(errorResponse(
 *     ErrorCode.INVALID_TOKEN,
 *     'Token is invalid or expired',
 *     requestId,
 *     { retryable: true, retryAfter: 5000 }
 *   ));
 * }
 */
export function errorResponse(
  code: ErrorCode | string,
  message: string,
  requestId: string,
  options: {
    retryable?: boolean;
    retryAfter?: number;
    details?: Record<string, any>;
  } = {}
): APIResponse<null> {
  return {
    status: 'error',
    data: null,
    error: {
      code,
      message,
      retryable: options.retryable ?? false,
      retryAfter: options.retryAfter,
      details: options.details,
    },
    metadata: {
      requestId,
      timestamp: new Date().toISOString(),
      version: 'v1',
    },
  };
}

/**
 * Helper to create partial response (data with warnings)
 * 
 * @param data - Response payload
 * @param warnings - Array of warning messages
 * @param requestId - Request ID for tracing
 * @returns APIResponse<T>
 * 
 * @example
 * const creds = [...]; // may include revoked credentials
 * return res.status(200).json(partialResponse(
 *   creds,
 *   ['1 credential has expired and was excluded'],
 *   requestId
 * ));
 */
export function partialResponse<T>(
  data: T,
  warnings: string[],
  requestId: string
): APIResponse<T> {
  return {
    status: 'partial',
    data,
    error: null,
    metadata: {
      requestId,
      timestamp: new Date().toISOString(),
      version: 'v1',
      warnings,
    },
  };
}

/**
 * Error code to HTTP Status mapping for route handlers
 */
export const ErrorCodeToHttpStatus: Record<string, HttpStatus> = {
  [ErrorCode.INVALID_TOKEN]: HttpStatus.UNAUTHORIZED,
  [ErrorCode.TOKEN_EXPIRED]: HttpStatus.UNAUTHORIZED,
  [ErrorCode.PERMISSION_DENIED]: HttpStatus.FORBIDDEN,
  [ErrorCode.MISSING_CREDENTIALS]: HttpStatus.UNAUTHORIZED,
  [ErrorCode.ROTATION_FAILED]: HttpStatus.INTERNAL_SERVER_ERROR,
  [ErrorCode.NOT_FOUND]: HttpStatus.NOT_FOUND,
  [ErrorCode.QUOTA_EXHAUSTED]: HttpStatus.CONFLICT,
  [ErrorCode.INVALID_TYPE]: HttpStatus.BAD_REQUEST,
  [ErrorCode.INVALID_REQUEST]: HttpStatus.BAD_REQUEST,
  [ErrorCode.MISSING_REQUIRED_FIELD]: HttpStatus.BAD_REQUEST,
  [ErrorCode.INVALID_FORMAT]: HttpStatus.BAD_REQUEST,
  [ErrorCode.INTERNAL_ERROR]: HttpStatus.INTERNAL_SERVER_ERROR,
  [ErrorCode.UNAVAILABLE]: HttpStatus.SERVICE_UNAVAILABLE,
  [ErrorCode.RATE_LIMITED]: HttpStatus.TOO_MANY_REQUESTS,
  [ErrorCode.GATEWAY_TIMEOUT]: HttpStatus.GATEWAY_TIMEOUT,
};

/**
 * Get HTTP status code from error code
 */
export function getHttpStatus(errorCode: string): HttpStatus {
  return ErrorCodeToHttpStatus[errorCode] ?? HttpStatus.INTERNAL_SERVER_ERROR;
}
