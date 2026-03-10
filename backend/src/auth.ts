/**
 * Authentication Module
 * Handles OAuth 2.0 (Google, GitHub), JWT tokens, and session management
 * Implements immutable, ephemeral, idempotent authentication flows
 */

import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import crypto from 'crypto';
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

// ============================================================================
// TYPE DEFINITIONS
// ============================================================================

export interface AuthenticatedRequest extends Request {
  userId?: string;
  userEmail?: string;
  userRole?: string;
  token?: string;
}

export interface JWTPayload {
  userId: string;
  email: string;
  role: string;
  iat: number;
  exp: number;
}

export interface OAuthProfile {
  id: string;
  email: string;
  name: string;
  picture?: string;
  provider: 'google' | 'github';
}

// ============================================================================
// JWT TOKEN MANAGEMENT
// ============================================================================

const JWT_SECRET = process.env.JWT_SECRET || 'dev-secret-key-change-in-production';
const JWT_EXPIRY = '24h';
const REFRESH_TOKEN_EXPIRY = '7d';

/**
 * Generate JWT token (ephemeral, time-limited)
 */
export function generateToken(userId: string, email: string, role: string): string {
  return jwt.sign(
    {
      userId,
      email,
      role,
    },
    JWT_SECRET,
    {
      expiresIn: JWT_EXPIRY,
      issuer: 'nexusshield-portal',
      audience: 'nexusshield-api',
    }
  );
}

/**
 * Verify JWT token (idempotent - same input always produces same validation result)
 */
export function verifyToken(token: string): JWTPayload | null {
  try {
    const payload = jwt.verify(token, JWT_SECRET, {
      issuer: 'nexusshield-portal',
      audience: 'nexusshield-api',
    }) as JWTPayload;
    return payload;
  } catch (error: any) {
    console.log(`❌ Token verification failed: ${error.message}`);
    return null;
  }
}

/**
 * Middleware: Require authentication (Bearer token in Authorization header)
 */
export function authenticationRequired(
  req: AuthenticatedRequest,
  res: Response,
  next: NextFunction
) {
  const authHeader = req.headers.authorization;

  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({
      error: 'Unauthorized',
      message: 'Missing or invalid Authorization header (expected: Bearer <token>)',
    });
  }

  const token = authHeader.substring(7); // Remove "Bearer " prefix
  const payload = verifyToken(token);

  if (!payload) {
    return res.status(401).json({
      error: 'Unauthorized',
      message: 'Invalid or expired token',
    });
  }

  // Attach user info to request (immutable - read-only properties)
  Object.defineProperties(req, {
    userId: { value: payload.userId, writable: false },
    userEmail: { value: payload.email, writable: false },
    userRole: { value: payload.role, writable: false },
    token: { value: token, writable: false },
  });

  next();
}

/**
 * Middleware: Require specific role (admin, editor, viewer)
 */
export function requireRole(...allowedRoles: string[]) {
  return (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
    if (!req.userRole || !allowedRoles.includes(req.userRole)) {
      return res.status(403).json({
        error: 'Forbidden',
        message: `Insufficient permissions. Required role: ${allowedRoles.join(' or ')}`,
      });
    }
    next();
  };
}

// ============================================================================
// OAUTH 2.0 AUTHENTICATION
// ============================================================================

/**
 * OAuth 2.0 callback handler (Google/GitHub)
 * Idempotent: same OAuth profile always creates/returns same user
 */
export async function handleOAuthCallback(
  profile: OAuthProfile
): Promise<{ user: any; token: string }> {
  try {
    // Find or create user (idempotent)
    const user = await prisma.user.upsert({
      where: { email: profile.email },
      update: {
        name: profile.name,
        last_login: new Date(),
        oauth_id: profile.id,
        oauth_provider: profile.provider,
      },
      create: {
        email: profile.email,
        name: profile.name,
        oauth_id: profile.id,
        oauth_provider: profile.provider,
        role: 'viewer', // Default role for new users
      },
    });

    // Generate JWT token
    const token = generateToken(user.id, user.email, user.role);

    return {
      user: {
        id: user.id,
        email: user.email,
        name: user.name,
        role: user.role,
      },
      token,
    };
  } catch (error: any) {
    throw new Error(`OAuth callback failed: ${error.message}`);
  }
}

/**
 * Revoke token (logout) - Idempotent
 * Re-revoking same token is safe (no state change)
 */
export async function revokeToken(token: string): Promise<void> {
  // In production: add to Redis blacklist or database
  // For now: just verify it exists and is valid
  const payload = verifyToken(token);
  if (!payload) {
    throw new Error('Token already invalid or expired');
  }
  // Success: token is now considered revoked (caller should discard it)
}

// ============================================================================
// SESSION MANAGEMENT
// ============================================================================

/**
 * Create session (ephemeral, time-limited)
 */
export async function createSession(
  userId: string,
  user_agent?: string,
  ip_address?: string
): Promise<{ sessionId: string; expiresAt: Date }> {
  const sessionId = crypto.randomUUID();
  const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000); // 7 days

  // In production: store in database or Redis
  // For now: return ephemeral session
  return {
    sessionId,
    expiresAt,
  };
}

/**
 * Verify session is still valid (idempotent)
 */
export async function verifySession(sessionId: string): Promise<boolean> {
  // In production: check database or Redis
  // For now: verify format is valid UUID
  const uuidRegex =
    /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  return uuidRegex.test(sessionId);
}

// ============================================================================
// PERMISSION CHECKS (RBAC)
// ============================================================================

/**
 * Check if user has specific permission
 */
export async function hasPermission(userId: string, permission: string): Promise<boolean> {
  try {
    const user = await prisma.user.findUnique({ where: { id: userId } });
    if (!user || !user.permissions) return false;
    return user.permissions.includes(permission);
  } catch (error) {
    return false;
  }
}

/**
 * Grant permission to user (idempotent - adding existing permission is safe)
 */
export async function grantPermission(userId: string, permission: string): Promise<void> {
  try {
    const user = await prisma.user.findUnique({ where: { id: userId } });
    if (!user) throw new Error('User not found');

    const permissions = new Set(user.permissions || []);
    permissions.add(permission);

    await prisma.user.update({
      where: { id: userId },
      data: { permissions: Array.from(permissions) },
    });
  } catch (error: any) {
    throw new Error(`Failed to grant permission: ${error.message}`);
  }
}

/**
 * Revoke permission from user (idempotent - revoking non-existent permission is safe)
 */
export async function revokePermission(userId: string, permission: string): Promise<void> {
  try {
    const user = await prisma.user.findUnique({ where: { id: userId } });
    if (!user) throw new Error('User not found');

    const permissions = new Set(user.permissions || []);
    permissions.delete(permission);

    await prisma.user.update({
      where: { id: userId },
      data: { permissions: Array.from(permissions) },
    });
  } catch (error: any) {
    throw new Error(`Failed to revoke permission: ${error.message}`);
  }
}

export default {
  generateToken,
  verifyToken,
  authenticationRequired,
  requireRole,
  handleOAuthCallback,
  revokeToken,
  createSession,
  verifySession,
  hasPermission,
  grantPermission,
  revokePermission,
};
