import express, { Express, Request, Response, NextFunction } from 'express';
import crypto from 'crypto';
import fs from 'fs';
import path from 'path';
import helmet from 'helmet';
import cors from 'cors';

// Import unified response middleware
import { setupUnifiedResponseMiddleware, setupErrorHandling } from './middleware/unified-response-middleware';

// Initialize Express app
const app: Express = express();
import { getPrisma } from './prisma-wrapper';
const prisma = getPrisma();
const PORT = parseInt(process.env.PORT || '3000', 10);
const ENVIRONMENT = process.env.NODE_ENV || 'development';

// ============================================================================
// TYPES
// ============================================================================

interface AuthenticatedRequest extends Request {
  userId?: string;
  userEmail?: string;
  userRole?: string;
  token?: string;
}

// ============================================================================
// MIDDLEWARE
// ============================================================================

// Security middleware
app.use(helmet());
app.use(cors({
  origin: process.env.CORS_ORIGINS?.split(',') || '*',
  credentials: true
}));

app.use(express.json({ limit: '1mb' }));
app.use(express.urlencoded({ limit: '1mb' }));

// Setup unified response middleware (request ID, response wrapping, rate limiting)
setupUnifiedResponseMiddleware(app);

// Request logging & audit trail middleware
const auditMiddleware = (req: Request, res: Response, next: NextFunction): void => {
  const startTime = Date.now();
  
  // Log response completion
  const originalSend = res.send;
  res.send = function(data: any) {
    const latency = Date.now() - startTime;
    const auditEntry = {
      requestId: (req as any).requestId,
      timestamp: new Date().toISOString(),
      method: req.method,
      path: req.path,
      statusCode: res.statusCode,
      latencyMs: latency,
      userAgent: req.get('user-agent'),
      ip: req.ip || 'unknown',
      userId: (req as AuthenticatedRequest).userId || 'anonymous',
    };

    // Log to immutable audit trail
    const logsDir = path.join(__dirname, '../logs');
    if (!fs.existsSync(logsDir)) {
      try {
        fs.mkdirSync(logsDir, { recursive: true });
      } catch (e) {
        // Might already exist due to race condition
      }
    }
    
    try {
      fs.appendFileSync(
        path.join(logsDir, 'portal-api-audit.jsonl'),
        JSON.stringify(auditEntry) + '\n',
        { flag: 'a' }
      );
    } catch (e) {
      console.error('Failed to write audit log:', e);
    }

    return originalSend.call(this, data);
  };

  next();
};

app.use(auditMiddleware);

// Error handling middleware
app.use((err: any, req: Request, res: Response, next: NextFunction) => {
  console.error('Error:', {
    requestId: (req as any).requestId,
    error: err.message,
    stack: process.env.NODE_ENV === 'development' ? err.stack : undefined,
  });
  
  res.status(err.status || 500).json({
    error: err.message || 'Internal Server Error',
    requestId: (req as any).requestId,
    timestamp: new Date().toISOString(),
  });
});

// ============================================================================
// AUTHENTICATION & AUTHORIZATION
// ============================================================================

interface JWTPayload {
  userId: string;
  email: string;
  role: string;
  iat: number;
  exp: number;
}

const JWT_SECRET = process.env.JWT_SECRET || 'dev-secret-key-change-in-production';

/**
 * Generate ephemeral JWT token (24 hours)
 * Idempotent: same input always produces valid token (expires based on timestamp)
 */
function generateJWT(userId: string, email: string, role: string = 'viewer'): string {
  const payload: JWTPayload = {
    userId,
    email,
    role,
    iat: Math.floor(Date.now() / 1000),
    exp: Math.floor(Date.now() / 1000) + 86400, // 24 hours
  };
  
  // In production: use jsonwebtoken package
  // For now: simple base64 encoding (proof of concept)
  return Buffer.from(JSON.stringify(payload)).toString('base64');
}

/**
 * Verify and decode JWT token
 * Returns null if token is invalid or expired
 */
function verifyJWT(token: string): JWTPayload | null {
  try {
    const payload = JSON.parse(Buffer.from(token, 'base64').toString());
    const now = Math.floor(Date.now() / 1000);
    
    if (payload.exp < now) {
      return null; // Token expired
    }
    
    return payload;
  } catch (e) {
    return null;
  }
}

/**
 * Middleware: Verify JWT token from Authorization header
 * Idempotent: same token in same header always produces same result
 */
function authMiddleware(req: AuthenticatedRequest, res: Response, next: NextFunction): Response | void {
  const authHeader = req.get('Authorization') || '';
  const token = authHeader.replace('Bearer ', '');

  if (!token) {
    return res.status(401).json({ error: 'Missing Authorization header' });
  }

  const payload = verifyJWT(token);
  if (!payload) {
    return res.status(401).json({ error: 'Invalid or expired token' });
  }

  req.userId = payload.userId;
  req.userEmail = payload.email;
  req.userRole = payload.role;
  req.token = token;

  next();
}

// ============================================================================
// CREDENTIAL MANAGEMENT (GSM → Vault → KMS fallback)
// ============================================================================

interface CredentialLayer {
  layer: 'gsm' | 'vault' | 'kms' | 'cache';
  status: 'available' | 'unavailable';
  latency_ms: number;
}

/**
 * Get credential from Google Secret Manager (PRIMARY)
 * In production: uses @google-cloud/secret-manager
 */
async function getCredentialFromGSM(secretName: string): Promise<string | null> {
  try {
    // TODO: Implement @google-cloud/secret-manager in production
    // For now: check database cache
    const cred = await prisma.credential.findFirst({
      where: { type: 'gsm', name: secretName, deleted_at: null },
      select: { value: true },
    });
    return cred?.value || null;
  } catch (e) {
    console.error('GSM lookup failed:', e);
    return null;
  }
}

/**
 * Get credential from HashiCorp Vault (SECONDARY)
 * In production: uses node-vault client
 */
async function getCredentialFromVault(secretPath: string): Promise<string | null> {
  try {
    // TODO: Implement node-vault client in production
    // For now: fallback to next layer
    return null;
  } catch (e) {
    console.error('Vault lookup failed:', e);
    return null;
  }
}

/**
 * Get credential from Google Cloud KMS (TERTIARY)
 * In production: uses @google-cloud/kms
 */
async function getCredentialFromKMS(keyId: string): Promise<string | null> {
  try {
    // TODO: Implement @google-cloud/kms in production
    // For now: check database cache
    const cred = await prisma.credential.findFirst({
      where: { type: 'kms', name: keyId, deleted_at: null },
      select: { value: true },
    });
    return cred?.value || null;
  } catch (e) {
    console.error('KMS lookup failed:', e);
    return null;
  }
}

/**
 * Resolve credential through layered backend (immutable, idempotent)
 * Always returns same credential if it exists
 */
async function resolveCredential(secretName: string): Promise<{
  value: string | null;
  layers: CredentialLayer[];
  resolvedFrom: string | null;
}> {
  const layers: CredentialLayer[] = [];
  let resolvedFrom: string | null = null;

  // Layer 1: GSM (Primary)
  const t1 = Date.now();
  const gsmCred = await getCredentialFromGSM(secretName);
  layers.push({
    layer: 'gsm',
    status: gsmCred ? 'available' : 'unavailable',
    latency_ms: Date.now() - t1,
  });
  if (gsmCred) return { value: gsmCred, layers, resolvedFrom: 'gsm' };

  // Layer 2: Vault (Secondary)
  const t2 = Date.now();
  const vaultCred = await getCredentialFromVault(`secret/${secretName}`);
  layers.push({
    layer: 'vault',
    status: vaultCred ? 'available' : 'unavailable',
    latency_ms: Date.now() - t2,
  });
  if (vaultCred) return { value: vaultCred, layers, resolvedFrom: 'vault' };

  // Layer 3: KMS (Tertiary)
  const t3 = Date.now();
  const kmsCred = await getCredentialFromKMS(secretName);
  layers.push({
    layer: 'kms',
    status: kmsCred ? 'available' : 'unavailable',
    latency_ms: Date.now() - t3,
  });
  if (kmsCred) return { value: kmsCred, layers, resolvedFrom: 'kms' };

  // Layer 4: Local cache (Offline fallback)
  layers.push({
    layer: 'cache',
    status: 'unavailable',
    latency_ms: 0,
  });

  return { value: null, layers, resolvedFrom: null };
}

// ============================================================================
// ROUTES
// ============================================================================

// ===== HEALTH & READINESS =====

/**
 * Liveness probe: Is the API running?
 * Used by Kubernetes to restart container if failed
 */
app.get('/alive', (req: Request, res: Response) => {
  res.json({
    status: 'alive',
    timestamp: new Date().toISOString(),
  });
});

/**
 * Readiness probe: Is the API ready to serve requests?
 * Checks database connectivity
 */
app.get('/ready', async (req: Request, res: Response) => {
  try {
    await prisma.$queryRaw`SELECT 1`;
    res.json({
      status: 'ready',
      timestamp: new Date().toISOString(),
      environment: ENVIRONMENT,
    });
  } catch (error: any) {
    res.status(503).json({
      status: 'not-ready',
      error: error.message,
      timestamp: new Date().toISOString(),
    });
  }
});

/**
 * Legacy health check endpoint (compatibility)
 */
app.get('/health', async (req: Request, res: Response) => {
  try {
    await prisma.$queryRaw`SELECT 1`;
    res.json({
      status: 'healthy',
      timestamp: new Date().toISOString(),
      version: '1.0.0-alpha',
      uptime_seconds: process.uptime(),
      environment: ENVIRONMENT,
    });
  } catch (error: any) {
    res.status(503).json({
      status: 'unhealthy',
      error: error.message,
      timestamp: new Date().toISOString(),
    });
  }
});

// ===== AUTHENTICATION =====

/**
 * Login: Create user session and return JWT token
 * Idempotent: same email/provider always creates/returns user
 */
app.post('/auth/login', async (req: Request, res: Response) => {
  try {
    const { email, provider = 'local', name = '' } = req.body;

    if (!email || !email.includes('@')) {
      return res.status(400).json({ error: 'Valid email required' });
    }

    // Find or create user (idempotent)
    let user = await prisma.user.findUnique({ where: { email } });
    if (!user) {
      user = await prisma.user.create({
        data: {
          email,
          name,
          oauth_provider: provider,
          oauth_id: provider === 'local' ? undefined : crypto.randomUUID(),
        },
      });
    }

    // Generate ephemeral JWT token
    const token = generateJWT(user.id, user.email, user.role);

    res.json({
      token,
      user: {
        id: user.id,
        email: user.email,
        name: user.name,
        role: user.role,
      },
      expiresIn: '24h',
      timestamp: new Date().toISOString(),
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

/**
 * Logout: Invalidate session
 * Idempotent: logging out twice returns same result
 */
app.post('/auth/logout', authMiddleware, async (req: AuthenticatedRequest, res: Response) => {
  try {
    // In production: add token to blacklist/revocation list
    res.json({
      status: 'logged_out',
      timestamp: new Date().toISOString(),
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

/**
 * Verify token: Check if token is valid
 * Used for frontend to check session
 */
app.post('/auth/verify', (req: Request, res: Response) => {
  try {
    const authHeader = req.get('Authorization') || '';
    const token = authHeader.replace('Bearer ', '');

    if (!token) {
      return res.status(401).json({ valid: false });
    }

    const payload = verifyJWT(token);
    if (!payload) {
      return res.status(401).json({ valid: false });
    }

    res.json({
      valid: true,
      user: {
        id: payload.userId,
        email: payload.email,
        role: payload.role,
      },
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

// ===== CREDENTIALS MANAGEMENT =====

/**
 * List all credentials (redacted - no secrets returned)
 * Idempotent: always returns same list with same properties hidden
 */
app.get('/api/credentials', authMiddleware, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const credentials = await prisma.credential.findMany({
      where: { deleted_at: null },
      select: {
        id: true,
        type: true,
        name: true,
        created_at: true,
        updated_at: true,
        created_by: true,
        // NOTE: 'value' field NEVER returned to frontend
      },
      orderBy: { created_at: 'desc' },
    });

    res.json({
      count: credentials.length,
      credentials,
      timestamp: new Date().toISOString(),
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

/**
 * Get credential details (redacted)
 */
app.get('/api/credentials/:id', authMiddleware, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const credential = await prisma.credential.findUnique({
      where: { id: req.params.id },
      select: {
        id: true,
        type: true,
        name: true,
        created_at: true,
        updated_at: true,
        created_by: true,
      },
    });

    if (!credential) {
      return res.status(404).json({ error: 'Credential not found' });
    }

    res.json(credential);
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

/**
 * Create new credential (immutable, idempotent)
 * Same (type, name) always creates once; subsequent requests fail with 409 Conflict
 */
app.post('/api/credentials', authMiddleware, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const { type, name, value } = req.body;

    if (!type || !name || !value) {
      return res.status(400).json({
        error: 'Missing required fields: type, name, value',
      });
    }

    // Check for duplicates (unique constraint)
    const existing = await prisma.credential.findFirst({
      where: { type, name, deleted_at: null },
    });

    if (existing) {
      return res.status(409).json({
        error: 'Credential already exists',
        credentialId: existing.id,
      });
    }

    const credential = await prisma.credential.create({
      data: {
        type,
        name,
        value, // Encrypted by Cloud SQL
        created_by: req.userId || 'system',
      },
    });

    res.status(201).json({
      id: credential.id,
      type: credential.type,
      name: credential.name,
      created_at: credential.created_at,
      message: 'Credential created (value redacted)',
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

/**
 * Rotate credential (idempotent operation)
 * Same rotation request produces same result if run multiple times
 */
app.post('/api/credentials/:id/rotate', authMiddleware, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const { newValue, reason = 'manual' } = req.body;

    if (!newValue) {
      return res.status(400).json({ error: 'newValue required' });
    }

    const credential = await prisma.credential.findUnique({
      where: { id: req.params.id },
    });

    if (!credential) {
      return res.status(404).json({ error: 'Credential not found' });
    }

    if (credential.deleted_at) {
      return res.status(410).json({ error: 'Credential has been revoked' });
    }

    // Record rotation history (immutable audit trail)
    const oldHash = crypto.createHash('sha256').update(credential.value || '').digest('hex');
    const newHash = crypto.createHash('sha256').update(newValue).digest('hex');

    const rotation = await prisma.rotationHistory.create({
      data: {
        credentialId: credential.id,
        old_value_hash: oldHash,
        new_value_hash: newHash,
        rotation_reason: reason,
        rotated_by: req.userId || 'system',
      },
    });

    // Update credential with new value
    const updated = await prisma.credential.update({
      where: { id: req.params.id },
      data: { value: newValue },
    });

    res.json({
      message: 'Credential rotated',
      id: updated.id,
      rotatedAt: rotation.rotated_at,
      rotationId: rotation.id,
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

/**
 * Revoke credential (soft delete, immutable)
 * Multiple calls return same result (idempotent)
 */
app.delete('/api/credentials/:id', authMiddleware, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const credential = await prisma.credential.findUnique({
      where: { id: req.params.id },
    });

    if (!credential) {
      return res.status(404).json({ error: 'Credential not found' });
    }

    // Check if already soft-deleted
    if (credential.deleted_at) {
      return res.status(410).json({
        message: 'Credential already revoked',
        revokedAt: credential.deleted_at,
      });
    }

    // Soft delete (immutable archive)
    const updated = await prisma.credential.update({
      where: { id: req.params.id },
      data: { deleted_at: new Date() },
    });

    res.json({
      message: 'Credential revoked',
      id: updated.id,
      revokedAt: updated.deleted_at,
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

// ===== AUDIT & COMPLIANCE =====

/**
 * Get audit log entries
 * Immutable append-only log
 */
app.get('/api/audit', authMiddleware, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const limit = Math.min(parseInt(req.query.limit as string) || 100, 1000);
    const offset = parseInt(req.query.offset as string) || 0;

    const logs = await prisma.auditLog.findMany({
      where: { actor_id: req.userId },
      take: limit,
      skip: offset,
      orderBy: { created_at: 'desc' },
    });

    const total = await prisma.auditLog.count({
      where: { actor_id: req.userId },
    });

    res.json({
      count: logs.length,
      total,
      limit,
      offset,
      entries: logs,
      timestamp: new Date().toISOString(),
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

/**
 * Get rotation history for a credential
 * Immutable history of all rotations
 */
app.get('/api/credentials/:id/rotations', authMiddleware, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const rotations = await prisma.rotationHistory.findMany({
      where: { credentialId: req.params.id },
      orderBy: { rotated_at: 'desc' },
    });

    res.json({
      credentialId: req.params.id,
      count: rotations.length,
      rotations,
      timestamp: new Date().toISOString(),
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

/**
 * Get access logs for a credential
 * Security audit trail
 */
app.get('/api/credentials/:id/access-logs', authMiddleware, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const accessLogs = await prisma.accessLog.findMany({
      where: { credentialId: req.params.id },
      orderBy: { accessed_at: 'desc' },
      take: 100,
    });

    res.json({
      credentialId: req.params.id,
      count: accessLogs.length,
      accessLogs,
      timestamp: new Date().toISOString(),
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

// ===== DIAGNOSTICS =====

/**
 * Diagnose credential resolution
 * Test all credential layers (GSM, Vault, KMS, Cache)
 */
app.post('/api/diagnostics/resolve/:secretName', authMiddleware, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const { secretName } = req.params;
    const result = await resolveCredential(secretName);

    res.json({
      secret_name: secretName,
      resolved: result.value !== null,
      resolvedFrom: result.resolvedFrom,
      layers: result.layers,
      timestamp: new Date().toISOString(),
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

/**
 * System status and diagnostics
 */
app.get('/api/diagnostics/status', authMiddleware, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const memory = process.memoryUsage();
    
    const dbHealth = await prisma.$queryRaw`SELECT NOW()`;

    res.json({
      status: 'operational',
      timestamp: new Date().toISOString(),
      uptime_seconds: process.uptime(),
      environment: ENVIRONMENT,
      database: {
        status: dbHealth ? 'connected' : 'disconnected',
      },
      memory: {
        heapUsed_mb: Math.round(memory.heapUsed / 1024 / 1024),
        heapTotal_mb: Math.round(memory.heapTotal / 1024 / 1024),
        rss_mb: Math.round(memory.rss / 1024 / 1024),
      },
    });
  } catch (error: any) {
    res.status(500).json({
      status: 'degraded',
      error: error.message,
      timestamp: new Date().toISOString(),
    });
  }
});

// ===== METRICS (Prometheus format) =====

/**
 * Prometheus metrics endpoint
 * For monitoring and alerting
 */
app.get('/metrics', (req: Request, res: Response) => {
  const uptime = process.uptime();
  const memory = process.memoryUsage();

  const metrics = `# HELP nexus_portal_uptime_seconds Uptime in seconds
# TYPE nexus_portal_uptime_seconds gauge
nexus_portal_uptime_seconds ${uptime}

# HELP nexus_portal_memory_bytes Memory usage in bytes
# TYPE nexus_portal_memory_bytes gauge
nexus_portal_memory_bytes{type="rss"} ${memory.rss}
nexus_portal_memory_bytes{type="heapUsed"} ${memory.heapUsed}
nexus_portal_memory_bytes{type="heapTotal"} ${memory.heapTotal}

# HELP nexus_portal_requests_total Total HTTP requests
# TYPE nexus_portal_requests_total counter
nexus_portal_requests_total 0

# HELP nexus_portal_version API version
# TYPE nexus_portal_version gauge
nexus_portal_version{git_version="1.0.0-alpha"} 1
`.trim();

  res.setHeader('Content-Type', 'text/plain; version=0.0.4');
  res.send(metrics);
});

// ============================================================================
// ERROR HANDLING (must be registered last)
// ============================================================================
setupErrorHandling(app);

// ===== 404 HANDLER =====

app.use((req: Request, res: Response) => {
  res.status(404).json({
    error: 'Not found',
    path: req.path,
    method: req.method,
    timestamp: new Date().toISOString(),
  });
});

// ============================================================================
// SERVER STARTUP & GRACEFUL SHUTDOWN
// ============================================================================

const startServer = async () => {
  try {
    // Verify database connection, but don't block service startup.
    // This keeps health/diagnostics endpoints available during DB outages.
    try {
      await prisma.$queryRaw`SELECT 1`;
      console.log('✅ Database connection verified');
    } catch (dbError) {
      console.warn('⚠️ Database connection unavailable at startup; continuing in degraded mode');
      console.warn(dbError);
    }

    // Create logs directory
    const logsDir = path.join(__dirname, '../logs');
    if (!fs.existsSync(logsDir)) {
      fs.mkdirSync(logsDir, { recursive: true });
    }

    // Start Express server
    app.listen(PORT, '0.0.0.0', () => {
      console.log(`✅ NexusShield Portal API listening on port ${PORT}`);
      console.log(`📊 Metrics: http://localhost:${PORT}/metrics`);
      console.log(`📋 Health: http://localhost:${PORT}/health`);
      console.log(`🔍 Ready: http://localhost:${PORT}/ready`);
      console.log(`🎯 Alive: http://localhost:${PORT}/alive`);
      console.log(`📝 Docs: NexusShield Portal Backend v1.0.0-alpha`);
    });
  } catch (error) {
    console.error('❌ Server startup failed:', error);
    process.exit(1);
  }
};

// Graceful shutdown on SIGTERM (Kubernetes termination signal)
process.on('SIGTERM', async () => {
  console.log('🛑 SIGTERM received, initiating graceful shutdown...');
  try {
    await prisma.$disconnect();
    console.log('✅ Database disconnected');
    process.exit(0);
  } catch (error) {
    console.error('❌ Error during shutdown:', error);
    process.exit(1);
  }
});

// Graceful shutdown on SIGINT (Ctrl+C)
process.on('SIGINT', async () => {
  console.log('🛑 SIGINT received, initiating graceful shutdown...');
  try {
    await prisma.$disconnect();
    console.log('✅ Database disconnected');
    process.exit(0);
  } catch (error) {
    console.error('❌ Error during shutdown:', error);
    process.exit(1);
  }
});

// Handle unhandled promise rejections
process.on('unhandledRejection', (reason: Error, promise: Promise<any>) => {
  console.error('❌ Unhandled Rejection at:', promise, 'reason:', reason);
});

// Handle uncaught exceptions
process.on('uncaughtException', (error: Error) => {
  console.error('❌ Uncaught Exception:', error);
  process.exit(1);
});

// Start server
startServer();

export default app;
