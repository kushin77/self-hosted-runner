import express, { Express, Request, Response, NextFunction } from 'express';
import { PrismaClient } from '@prisma/client';
import crypto from 'crypto';
import fs from 'fs';
import path from 'path';

// Initialize Express app
const app: Express = express();
const prisma = new PrismaClient();
const PORT = process.env.PORT || 3000;

// ============================================================================
// MIDDLEWARE
// ============================================================================

// Request logging & audit trail middleware
const auditMiddleware = (req: Request, res: Response, next: NextFunction) => {
  const auditEntry = {
    timestamp: new Date().toISOString(),
    method: req.method,
    path: req.path,
    userAgent: req.get('user-agent'),
    ip: req.ip || 'unknown',
    userId: (req as any).userId || 'anonymous',
  };

  // Log to immutable audit trail
  const auditLog = path.join(__dirname, '../logs/portal-api-audit.jsonl');
  fs.appendFileSync(auditLog, JSON.stringify(auditEntry) + '\n', { flag: 'a' });

  next();
};

// Express configuration
app.use(express.json());
app.use(auditMiddleware);

// Error handling middleware
app.use((err: any, req: Request, res: Response, next: NextFunction) => {
  console.error('Error:', err.message);
  res.status(err.status || 500).json({
    error: err.message,
    timestamp: new Date().toISOString(),
  });
});

// ============================================================================
// CREDENTIAL MANAGEMENT (GSM → Vault → KMS fallback)
// ============================================================================

interface CredentialLayer {
  layer: string;
  status: 'available' | 'unavailable';
  latency_ms: number;
}

async function getCredentialFromGSM(secretName: string): Promise<string | null> {
  try {
    // In production: use @google-cloud/secret-manager
    // For now: mock implementation
    const cred = await prisma.credential.findFirst({
      where: { type: 'gsm', name: secretName },
    });
    return cred?.value || null;
  } catch (e) {
    return null;
  }
}

async function getCredentialFromVault(path: string): Promise<string | null> {
  try {
    // In production: use node-vault client
    // For now: fallback to next layer
    return null;
  } catch (e) {
    return null;
  }
}

async function getCredentialFromKMS(keyId: string): Promise<string | null> {
  try {
    // In production: use @google-cloud/kms
    // For now: mock implementation
    const cred = await prisma.credential.findFirst({
      where: { type: 'kms', name: keyId },
    });
    return cred?.value || null;
  } catch (e) {
    return null;
  }
}

async function resolveCredential(secretName: string): Promise<{
  value: string | null;
  layers: CredentialLayer[];
}> {
  const layers: CredentialLayer[] = [];

  // Layer 1: GSM (Primary)
  const t1 = Date.now();
  const gsmCred = await getCredentialFromGSM(secretName);
  layers.push({
    layer: 'gsm',
    status: gsmCred ? 'available' : 'unavailable',
    latency_ms: Date.now() - t1,
  });
  if (gsmCred) return { value: gsmCred, layers };

  // Layer 2A: Vault (Secondary)
  const t2 = Date.now();
  const vaultCred = await getCredentialFromVault(`secret/${secretName}`);
  layers.push({
    layer: 'vault',
    status: vaultCred ? 'available' : 'unavailable',
    latency_ms: Date.now() - t2,
  });
  if (vaultCred) return { value: vaultCred, layers };

  // Layer 2B: KMS (Tertiary)
  const t3 = Date.now();
  const kmsCred = await getCredentialFromKMS(secretName);
  layers.push({
    layer: 'kms',
    status: kmsCred ? 'available' : 'unavailable',
    latency_ms: Date.now() - t3,
  });
  if (kmsCred) return { value: kmsCred, layers };

  // Layer 3: Local cache (Offline fallback)
  layers.push({
    layer: 'local-cache',
    status: 'unavailable',
    latency_ms: 0,
  });

  return { value: null, layers };
}

// ============================================================================
// ROUTES
// ============================================================================

// Health check (readiness probe)
app.get('/health', (req: Request, res: Response) => {
  res.json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    version: '1.0.0-alpha',
    uptime_seconds: process.uptime(),
  });
});

// Credentials: List all (with redaction)
app.get('/credentials', async (req: Request, res: Response) => {
  try {
    const credentials = await prisma.credential.findMany({
      select: {
        id: true,
        type: true,
        name: true,
        created_at: true,
        updated_at: true,
        // NOTE: 'value' field is never returned (redacted)
      },
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

// Credentials: Create new
app.post('/credentials', async (req: Request, res: Response) => {
  try {
    const { type, name, value } = req.body;

    if (!type || !name || !value) {
      return res.status(400).json({
        error: 'Missing required fields: type, name, value',
      });
    }

    const credential = await prisma.credential.create({
      data: {
        type,
        name,
        value, // Encrypted at DB level (Cloud SQL encryption)
        created_by: (req as any).userId || 'system',
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

// Credentials: Get details (value redacted)
app.get('/credentials/:id', async (req: Request, res: Response) => {
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

// Credentials: Revoke/Delete
app.delete('/credentials/:id', async (req: Request, res: Response) => {
  try {
    const credential = await prisma.credential.delete({
      where: { id: req.params.id },
    });

    res.json({
      message: 'Credential revoked',
      id: credential.id,
      deleted_at: new Date().toISOString(),
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

// Audit Trail: Query logs
app.get('/audit', async (req: Request, res: Response) => {
  try {
    const limit = parseInt(req.query.limit as string) || 100;
    const offset = parseInt(req.query.offset as string) || 0;

    const auditLog = path.join(__dirname, '../logs/portal-api-audit.jsonl');
    const lines = fs.readFileSync(auditLog, 'utf-8').split('\n').filter(Boolean);

    const entries = lines.slice(offset, offset + limit).map((line) => JSON.parse(line));

    res.json({
      count: entries.length,
      total: lines.length,
      limit,
      offset,
      entries,
      timestamp: new Date().toISOString(),
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

// Credential Resolution: Test all layers
app.post('/diagnose/:secretName', async (req: Request, res: Response) => {
  try {
    const { secretName } = req.params;
    const result = await resolveCredential(secretName);

    res.json({
      secret_name: secretName,
      resolved: result.value !== null,
      layers: result.layers,
      timestamp: new Date().toISOString(),
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

// Metrics: Prometheus-format
app.get('/metrics', (req: Request, res: Response) => {
  const uptime = process.uptime();
  const memory = process.memoryUsage();

  const metrics = `
# HELP nexus_portal_uptime_seconds Uptime in seconds
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
  `.trim();

  res.setHeader('Content-Type', 'text/plain; version=0.0.4');
  res.send(metrics);
});

// ============================================================================
// SERVER STARTUP
// ============================================================================

const startServer = async () => {
  try {
    // Verify database connection
    await prisma.$queryRaw`SELECT 1`;
    console.log('✅ Database connection verified');

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
    });
  } catch (error) {
    console.error('❌ Server startup failed:', error);
    process.exit(1);
  }
};

// Graceful shutdown
process.on('SIGTERM', async () => {
  console.log('SIGTERM received, shutting down gracefully...');
  await prisma.$disconnect();
  process.exit(0);
});

// Start server
startServer();

export default app;
