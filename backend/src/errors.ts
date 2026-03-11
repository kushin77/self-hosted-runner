/**
 * Unified Error Handling Service
 * Standardizes error codes, messages, and responses across the application
 * All errors inherit from ApplicationError for consistent handling
 */

/**
 * Application error base class
 * Provides standardized error handling with codes, HTTP status, and optional details
 *
 * @example
 * throw new ApplicationError('CRED_NOT_FOUND', 404, 'Secret not found', { credentialId: 'db_pass' });
 */
export class ApplicationError extends Error {
  /**
   * Creates a new ApplicationError
   * @param code - Machine-readable error code (e.g., 'CRED_NOT_FOUND')
   * @param statusCode - HTTP status code (200-599)
   * @param message - Human-readable error message
   * @param details - Optional additional error context
   * @param cause - Optional underlying error cause
   */
  constructor(
    public code: string,
    public statusCode: number,
    message: string,
    public details?: Record<string, any>,
    public cause?: Error,
  ) {
    super(message);
    this.name = 'ApplicationError';
    Object.setPrototypeOf(this, ApplicationError.prototype);
  }

  /**
   * Convert error to JSON response format
   * @returns Serializable error object suitable for HTTP response
   */
  toJSON() {
    return {
      code: this.code,
      message: this.message,
      statusCode: this.statusCode,
      timestamp: new Date().toISOString(),
      details: this.details,
    };
  }
}

/**
 * Authentication/Authorization errors (401, 403)
 */
export class AuthenticationError extends ApplicationError {
  /**
   * @param message - Error message
   * @param details - Optional context
   */
  constructor(
    message: string = 'Authentication failed',
    details?: Record<string, any>,
  ) {
    super('AUTH_FAILED', 401, message, details);
    this.name = 'AuthenticationError';
    Object.setPrototypeOf(this, AuthenticationError.prototype);
  }
}

export class AuthorizationError extends ApplicationError {
  /**
   * @param message - Error message
   * @param details - Optional context
   */
  constructor(
    message: string = 'Access denied',
    details?: Record<string, any>,
  ) {
    super('ACCESS_DENIED', 403, message, details);
    this.name = 'AuthorizationError';
    Object.setPrototypeOf(this, AuthorizationError.prototype);
  }
}

/**
 * Validation errors (400)
 */
export class ValidationError extends ApplicationError {
  /**
   * @param message - Error message
   * @param details - Validation failure details
   */
  constructor(
    message: string = 'Validation failed',
    details?: Record<string, any>,
  ) {
    super('VALIDATION_FAILED', 400, message, details);
    this.name = 'ValidationError';
    Object.setPrototypeOf(this, ValidationError.prototype);
  }
}

/**
 * Resource not found errors (404)
 */
export class NotFoundError extends ApplicationError {
  /**
   * @param resourceType - Type of resource not found
   * @param identifier - Resource identifier
   */
  constructor(resourceType: string, identifier: string) {
    super(
      `${resourceType.toUpperCase()}_NOT_FOUND`,
      404,
      `${resourceType} not found: ${identifier}`,
      { resourceType, identifier },
    );
    this.name = 'NotFoundError';
    Object.setPrototypeOf(this, NotFoundError.prototype);
  }
}

/**
 * Credential-specific errors
 */
export class CredentialError extends ApplicationError {
  /**
   * @param code - Error code
   * @param message - Error message
   * @param details - Optional context
   */
  constructor(
    code: string,
    message: string,
    details?: Record<string, any>,
  ) {
    super(code, 500, message, details);
    this.name = 'CredentialError';
    Object.setPrototypeOf(this, CredentialError.prototype);
  }
}

export class CredentialNotFoundError extends ApplicationError {
  /**
   * @param name - Credential name that wasn't found
   */
  constructor(name: string) {
    super(
      'CRED_NOT_FOUND',
      404,
      `Credential not found: ${name}`,
      { credentialName: name },
    );
    this.name = 'CredentialNotFoundError';
    Object.setPrototypeOf(this, CredentialNotFoundError.prototype);
  }
}

export class CredentialResolutionError extends ApplicationError {
  /**
   * When all credential layers (GSM, Vault, KMS) fail
   * @param name - Credential name
   * @param failedLayers - Which layers failed
   */
  constructor(name: string, failedLayers: string[]) {
    super(
      'CRED_RESOLUTION_FAILED',
      503,
      `Failed to resolve credential from all layers: ${name}`,
      { credentialName: name, failedLayers },
    );
    this.name = 'CredentialResolutionError';
    Object.setPrototypeOf(this, CredentialResolutionError.prototype);
  }
}

/**
 * Database/Prisma errors
 */
export class DatabaseError extends ApplicationError {
  /**
   * @param message - Error message
   * @param cause - Original database error
   * @param details - Optional context
   */
  constructor(
    message: string,
    cause?: Error,
    details?: Record<string, any>,
  ) {
    super(
      'DATABASE_ERROR',
      500,
      message,
      details,
      cause,
    );
    this.name = 'DatabaseError';
    Object.setPrototypeOf(this, DatabaseError.prototype);
  }
}

/**
 * External service errors (Vault, GSM, KMS)
 */
export class ExternalServiceError extends ApplicationError {
  /**
   * @param service - Name of external service
   * @param message - Error message
   * @param statusCode - HTTP status from service
   */
  constructor(service: string, message: string, statusCode: number = 500) {
    super(
      `${service.toUpperCase()}_ERROR`,
      statusCode,
      `${service} error: ${message}`,
      { service },
    );
    this.name = 'ExternalServiceError';
    Object.setPrototypeOf(this, ExternalServiceError.prototype);
  }
}

/**
 * Rate limiting errors (429)
 */
export class RateLimitError extends ApplicationError {
  /**
   * @param retryAfter - Seconds to wait before retry
   */
  constructor(retryAfter: number = 60) {
    super(
      'RATE_LIMIT_EXCEEDED',
      429,
      'Too many requests. Please try again later.',
      { retryAfterSeconds: retryAfter },
    );
    this.name = 'RateLimitError';
    Object.setPrototypeOf(this, RateLimitError.prototype);
  }
}

/**
 * Server error (500)
 */
export class ServerError extends ApplicationError {
  /**
   * @param message - Error message
   * @param cause - Original error
   */
  constructor(message: string = 'Internal server error', cause?: Error) {
    super(
      'INTERNAL_SERVER_ERROR',
      500,
      message,
      { cause: cause?.message },
      cause,
    );
    this.name = 'ServerError';
    Object.setPrototypeOf(this, ServerError.prototype);
  }
}

/**
 * Error code registry - maps codes to expected statuses
 * Useful for monitoring and error classification
 */
export const ERROR_CODES = {
  // Authentication
  AUTH_FAILED: 401,
  INVALID_TOKEN: 401,
  TOKEN_EXPIRED: 401,
  ACCESS_DENIED: 403,
  
  // Validation
  VALIDATION_FAILED: 400,
  INVALID_INPUT: 400,
  
  // Not Found
  NOT_FOUND: 404,
  CRED_NOT_FOUND: 404,
  
  // Credentials
  CRED_RESOLUTION_FAILED: 503,
  CRED_ALREADY_EXISTS: 409,
  CRED_ROTATION_FAILED: 500,
  
  // Database
  DATABASE_ERROR: 500,
  DATABASE_CONSTRAINT: 409,
  
  // External Services
  GSM_ERROR: 503,
  VAULT_ERROR: 503,
  KMS_ERROR: 503,
  
  // Rate Limiting
  RATE_LIMIT_EXCEEDED: 429,
  
  // Server
  INTERNAL_SERVER_ERROR: 500,
  SERVICE_UNAVAILABLE: 503,
} as const;

/**
 * Check if error is an ApplicationError
 * @param error - Error to check
 * @returns True if error is ApplicationError
 */
export function isApplicationError(error: unknown): error is ApplicationError {
  return error instanceof ApplicationError;
}

/**
 * Get HTTP status code for error
 * @param error - Error object
 * @returns HTTP status code (500 if unknown)
 */
export function getStatusCode(error: unknown): number {
  if (isApplicationError(error)) {
    return error.statusCode;
  }
  return 500;
}

/**
 * Get error code for error
 * @param error - Error object
 * @returns Error code string
 */
export function getErrorCode(error: unknown): string {
  if (isApplicationError(error)) {
    return error.code;
  }
  return 'INTERNAL_SERVER_ERROR';
}
