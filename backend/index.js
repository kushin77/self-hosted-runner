const http = require('http');
const url = require('url');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const PORT = process.env.PORT || 3000;
const { generateId, generateToken, logAuditEntry, auditTrail } = require('./lib/utils');

// In-memory stores (would be backed by PostgreSQL in production)
const credentials = new Map();
const users = new Map();
const sessions = new Map();

// Initialize demo data
function initializeDemoData() {
  // Demo user (admin)
  const adminId = generateId();
  users.set(adminId, {
    id: adminId,
    email: 'admin@nexusshield.cloud',
    role: 'admin',
    provider: 'oauth-google',
    createdAt: new Date().toISOString()
  });

  // Demo credentials
  credentials.set('cred-1', {
    id: 'cred-1',
    name: 'AWS Production Key',
    type: 'aws',
    createdAt: new Date().toISOString(),
    rotatedAt: new Date().toISOString(),
    nextRotation: new Date(Date.now() + 90 * 24 * 60 * 60 * 1000).toISOString(),
    status: 'active'
  });

  credentials.set('cred-2', {
    id: 'cred-2',
    name: 'GCP Service Account',
    type: 'gcp',
    createdAt: new Date().toISOString(),
    rotatedAt: new Date().toISOString(),
    nextRotation: new Date(Date.now() + 90 * 24 * 60 * 60 * 1000).toISOString(),
    status: 'active'
  });

  // Initialize audit trail
  auditTrail.push({
    id: generateId(),
    timestamp: new Date().toISOString(),
    action: 'system_init',
    resource: 'system',
    status: 'ok',
    userId: adminId,
    details: 'NexusShield Portal Backend initialized'
  });
}

// Logging & audit helpers are provided by backend/lib/utils.js

// Helper: Parse JSON body
function parseBody(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', chunk => body += chunk.toString());
    req.on('end', () => {
      try {
        resolve(body ? JSON.parse(body) : {});
      } catch (e) {
        reject(e);
      }
    });
  });
}

// Helper: Send JSON response
function sendJSON(res, statusCode, data) {
  res.writeHead(statusCode, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(data));
}

const server = http.createServer(async (req, res) => {
  const parsedUrl = url.parse(req.url, true);
  const pathname = parsedUrl.pathname;
  const method = req.method;

  // CORS headers
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (method === 'OPTIONS') {
    res.writeHead(200);
    res.end();
    return;
  }

  try {
    // ===== HEALTH & METRICS =====
    if (pathname === '/health' || pathname === '/api/health') {
      logAuditEntry('health_check', 'system', 'ok');
      return sendJSON(res, 200, {
        status: 'ok',
        timestamp: new Date().toISOString(),
        version: '1.0.0-alpha',
        uptime: process.uptime()
      });
    }

    if (pathname === '/metrics') {
      logAuditEntry('metrics_fetch', 'system', 'ok');
      const metrics = {
        http_requests_total: 0,
        credentials_total: credentials.size,
        audit_entries_total: auditTrail.length,
        uptime_seconds: process.uptime(),
        timestamp: new Date().toISOString()
      };
      const metricsText = Object.entries(metrics)
        .map(([k, v]) => `# HELP ${k}\n# TYPE ${k} gauge\n${k} ${v}`)
        .join('\n');
      res.writeHead(200, { 'Content-Type': 'text/plain' });
      res.end(metricsText);
      return;
    }

    // ===== AUTHENTICATION =====
    if (pathname === '/auth/login' && method === 'POST') {
      const body = await parseBody(req);
      const { provider, email } = body;
      const userId = generateId();
      const user = { id: userId, email: email || 'user@nexusshield.cloud', provider, role: 'viewer', createdAt: new Date().toISOString() };
      users.set(userId, user);
      const token = generateToken(userId);
      logAuditEntry('auth_login', 'user', 'ok', userId, `Login via ${provider}`);
      return sendJSON(res, 200, { token, user });
    }

    if (pathname === '/auth/logout' && method === 'POST') {
      const authHeader = req.headers.authorization || '';
      const token = authHeader.replace('Bearer ', '');
      sessions.delete(token);
      logAuditEntry('auth_logout', 'user', 'ok', null, 'Logout');
      return sendJSON(res, 200, { status: 'logged_out' });
    }

    // ===== CREDENTIALS MANAGEMENT =====
    if (pathname === '/api/credentials' && method === 'GET') {
      const list = Array.from(credentials.values());
      logAuditEntry('credentials_list', 'credentials', 'ok', null, `Listed ${list.length} credentials`);
      return sendJSON(res, 200, { credentials: list });
    }

    if (pathname.match(/^\/api\/credentials\/[\w-]+$/) && method === 'GET') {
      const credId = pathname.split('/').pop();
      const cred = credentials.get(credId);
      if (!cred) {
        logAuditEntry('credentials_get', 'credential', 'error_not_found', null, `Credential ${credId} not found`);
        return sendJSON(res, 404, { error: 'Credential not found' });
      }
      logAuditEntry('credentials_get', 'credential', 'ok', null, `Retrieved credential ${credId}`);
      return sendJSON(res, 200, cred);
    }

    if (pathname === '/api/credentials' && method === 'POST') {
      const body = await parseBody(req);
      const { name, type } = body;
      const credId = `cred-${generateId().slice(0, 8)}`;
      const cred = {
        id: credId,
        name,
        type,
        createdAt: new Date().toISOString(),
        rotatedAt: new Date().toISOString(),
        nextRotation: new Date(Date.now() + 90 * 24 * 60 * 60 * 1000).toISOString(),
        status: 'active'
      };
      credentials.set(credId, cred);
      logAuditEntry('credentials_create', 'credential', 'ok', null, `Created credential ${credId}`);
      return sendJSON(res, 201, cred);
    }

    if (pathname.match(/^\/api\/credentials\/[\w-]+\/rotate$/) && method === 'POST') {
      const credId = pathname.split('/')[3];
      const cred = credentials.get(credId);
      if (!cred) {
        return sendJSON(res, 404, { error: 'Credential not found' });
      }
      cred.rotatedAt = new Date().toISOString();
      cred.nextRotation = new Date(Date.now() + 90 * 24 * 60 * 60 * 1000).toISOString();
      credentials.set(credId, cred);
      logAuditEntry('credentials_rotate', 'credential', 'ok', null, `Rotated credential ${credId}`);
      return sendJSON(res, 200, { status: 'rotated', credential: cred });
    }

    if (pathname.match(/^\/api\/credentials\/[\w-]+$/) && method === 'DELETE') {
      const credId = pathname.split('/').pop();
      if (!credentials.has(credId)) {
        return sendJSON(res, 404, { error: 'Credential not found' });
      }
      credentials.delete(credId);
      logAuditEntry('credentials_delete', 'credential', 'ok', null, `Deleted credential ${credId}`);
      return sendJSON(res, 200, { status: 'deleted', id: credId });
    }

    // ===== AUDIT TRAIL =====
    if (pathname === '/api/audit' && method === 'GET') {
      const limit = parsedUrl.query.limit || 100;
      const entries = auditTrail.slice(-limit);
      logAuditEntry('audit_fetch', 'audit', 'ok', null, `Fetched ${entries.length} audit entries`);
      return sendJSON(res, 200, { entries, total: auditTrail.length });
    }

    if (pathname === '/api/audit/export' && method === 'GET') {
      let exported = 0;
      auditTrail.forEach(entry => {
        const logDir = '/home/akushnir/self-hosted-runner/logs';
        if (!fs.existsSync(logDir)) {
          fs.mkdirSync(logDir, { recursive: true });
        }
        try {
          fs.appendFileSync(
            path.join(logDir, 'portal-api-audit-export.jsonl'),
            JSON.stringify(entry) + '\n'
          );
          exported++;
        } catch(e) {
          console.error('Export error:', e.message);
        }
      });
      logAuditEntry('audit_export', 'audit', 'ok', null, `Exported ${exported} entries`);
      return sendJSON(res, 200, { status: 'exported', count: exported });
    }

    // ===== DEPLOYMENTS =====
    if (pathname === '/api/deployments' && method === 'GET') {
      const deployments = [
        {
          id: 'deploy-1',
          name: 'Production API v1.0.0',
          status: 'running',
          createdAt: new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString(),
          region: 'us-central1'
        },
        {
          id: 'deploy-2',
          name: 'Staging Frontend v1.0.0-alpha',
          status: 'running',
          createdAt: new Date(Date.now() - 3 * 24 * 60 * 60 * 1000).toISOString(),
          region: 'us-central1'
        }
      ];
      logAuditEntry('deployments_list', 'deployments', 'ok', null, `Listed ${deployments.length} deployments`);
      return sendJSON(res, 200, { deployments });
    }

    // ===== DEFAULT 404 =====
    logAuditEntry('http_404', 'route', 'not_found', null, `${method} ${pathname}`);
    return sendJSON(res, 404, { error: 'Not found', path: pathname });

  } catch (error) {
    console.error('API Error:', error);
    logAuditEntry('api_error', 'system', 'error', null, error.message);
    return sendJSON(res, 500, { error: 'Internal server error', message: error.message });
  }
});

// Initialize demo data
initializeDemoData();

server.listen(PORT, '0.0.0.0', () => {
  console.log(`NexusShield Portal Backend listening on port ${PORT}`);
  console.log(`API Documentation:`);
  console.log(`  - Health: GET http://localhost:${PORT}/health`);
  console.log(`  - Credentials: GET/POST http://localhost:${PORT}/api/credentials`);
  console.log(`  - Audit: GET http://localhost:${PORT}/api/audit`);
  console.log(`  - Metrics: GET http://localhost:${PORT}/metrics`);
  console.log(`  - Auth: POST http://localhost:${PORT}/auth/login`);
  console.log(`  - Deployments: GET http://localhost:${PORT}/api/deployments`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('SIGTERM received, shutting down gracefully');
  server.close(() => {
    console.log('Server closed');
    process.exit(0);
  });
});

process.on('SIGINT', () => {
  console.log('SIGINT received, shutting down gracefully');
  server.close(() => {
    console.log('Server closed');
    process.exit(0);
  });
});
