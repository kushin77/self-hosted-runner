/**
 * NexusShield TypeScript SDK - Main Index
 * Export all public types and classes
 */

export {
  NexusShieldClient,
  createClient,
  // Types
  APIResponse,
  ErrorPayload,
  ResponseMetadata,
  LoginRequest,
  LoginResponse,
  User,
  Credential,
  CreateCredentialRequest,
  RotateCredentialRequest,
  RotateCredentialResponse,
  HealthStatus,
  ClientConfig,
} from './client';

export { default } from './client';
