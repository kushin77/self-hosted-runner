/**
 * Input Validation Schemas
 * Using Zod for runtime type validation and documentation
 * All API request bodies validated with these schemas
 */

import { z } from 'zod';

/**
 * Authentication login request
 * @example
 * const creds = { email: "user@example.com", password: "SecurePass123!" }
 */
export const LoginSchema = z.object({
  email: z.string()
    .email('Invalid email format')
    .toLowerCase()
    .describe('User email address'),
  password: z.string()
    .min(8, 'Password must be at least 8 characters')
    .max(128, 'Password must be less than 128 characters')
    .describe('User password (minimum 8 characters)'),
});

export type LoginRequest = z.infer<typeof LoginSchema>;

/**
 * OAuth authorization request
 */
export const OAuthSchema = z.object({
  provider: z.enum(['google', 'github'], {
    errorMap: () => ({ message: 'Provider must be "google" or "github"' }),
  }).describe('OAuth provider'),
  code: z.string()
    .min(1, 'Authorization code required')
    .describe('OAuth authorization code from provider'),
  redirectUri: z.string()
    .url('Invalid redirect URI')
    .describe('Redirect URI from OAuth flow'),
});

export type OAuthRequest = z.infer<typeof OAuthSchema>;

/**
 * Credential access request (by name)
 */
export const CredentialAccessSchema = z.object({
  name: z.string()
    .min(1, 'Credential name required')
    .max(256, 'Credential name too long')
    .regex(/^[a-zA-Z0-9_\-\.]+$/, 'Invalid credential name format')
    .describe('Secret name/key (alphanumeric, underscore, dash, dot)'),
});

export type CredentialAccessRequest = z.infer<typeof CredentialAccessSchema>;

/**
 * Credential creation request
 */
export const CredentialCreateSchema = z.object({
  name: z.string()
    .min(1, 'Credential name required')
    .max(256, 'Credential name too long')
    .regex(/^[a-zA-Z0-9_\-\.]+$/, 'Invalid credential name format')
    .describe('Unique credential identifier'),
  value: z.string()
    .min(1, 'Credential value required')
    .max(10000, 'Credential value too large')
    .describe('Secret value (encrypted at rest)'),
  type: z.enum(['api_key', 'token', 'password', 'connection_string'], {
    errorMap: () => ({ message: 'Invalid credential type' }),
  }).describe('Credential classification'),
  metadata: z.record(z.string(), z.any())
    .optional()
    .describe('Optional metadata tags'),
});

export type CredentialCreateRequest = z.infer<typeof CredentialCreateSchema>;

/**
 * Credential rotation request
 */
export const CredentialRotationSchema = z.object({
  credentialId: z.string()
    .min(1, 'Credential ID required')
    .describe('Credential to rotate'),
  newValue: z.string()
    .min(1, 'New value required')
    .describe('New secret value'),
  reason: z.enum(['scheduled', 'manual', 'revoked', 'compromised', 'expired'], {
    errorMap: () => ({ message: 'Invalid rotation reason' }),
  }).describe('Reason for rotation'),
});

export type CredentialRotationRequest = z.infer<typeof CredentialRotationSchema>;

/**
 * Audit log query parameters
 */
export const AuditQuerySchema = z.object({
  action: z.enum(['created', 'rotated', 'accessed', 'revoked', 'diagnosed'])
    .optional()
    .describe('Filter by action type'),
  credentialId: z.string().optional().describe('Filter by credential ID'),
  actor: z.string().optional().describe('Filter by actor/user'),
  status: z.enum(['success', 'denied', 'failed']).optional().describe('Filter by status'),
  limit: z.number().int().min(1).max(1000).default(100).describe('Result limit'),
  offset: z.number().int().min(0).default(0).describe('Result offset for pagination'),
});

export type AuditQueryRequest = z.infer<typeof AuditQuerySchema>;

/**
 * Health check response (not user input, but documented for reference)
 */
export const HealthResponseSchema = z.object({
  status: z.enum(['healthy', 'degraded', 'unhealthy']),
  timestamp: z.string().datetime(),
  version: z.string(),
  checks: z.object({
    database: z.enum(['ok', 'failed']),
    vault: z.enum(['ok', 'failed']),
    gsm: z.enum(['ok', 'failed']),
  }),
});

export type HealthResponse = z.infer<typeof HealthResponseSchema>;

/**
 * Validation helper function
 * @param schema - Zod schema to validate against
 * @param data - Data to validate
 * @returns Validated and typed data or throws ZodError
 */
export function validate<T>(schema: z.ZodSchema<T>, data: unknown): T {
  return schema.parse(data);
}

/**
 * Safe validation (returns null on error instead of throwing)
 * @param schema - Zod schema to validate against
 * @param data - Data to validate
 * @returns Validated data or null if validation fails
 */
export function validateSafe<T>(
  schema: z.ZodSchema<T>,
  data: unknown,
): T | null {
  const result = schema.safeParse(data);
  return result.success ? result.data : null;
}
