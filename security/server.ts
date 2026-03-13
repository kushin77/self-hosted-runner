import { createServer, IncomingMessage, ServerResponse } from 'http';
import ZeroTrustAuth from './zero-trust-auth';

const port = Number(process.env.PORT || 8080);

const auth = new ZeroTrustAuth({
  oidcIssuer: process.env.JWT_ISSUER_URL || 'https://accounts.google.com',
  oidcAudience: process.env.JWT_AUDIENCE || 'zero-trust-auth',
  tokenTTL: Number(process.env.TOKEN_TTL || 3600),
  clockTolerance: Number(process.env.CLOCK_TOLERANCE || 30),
  ca: process.env.JWT_CA || 'dev-ca-placeholder',
  mtlsEnabled: (process.env.MTLS_ENABLED || 'false').toLowerCase() === 'true',
  revocationCheckInterval: Number(process.env.REVOCATION_CHECK_INTERVAL || 60),
});

function json(res: ServerResponse, code: number, body: unknown) {
  res.statusCode = code;
  res.setHeader('Content-Type', 'application/json');
  res.end(JSON.stringify(body));
}

function readBearer(req: IncomingMessage): string | null {
  const authHeader = req.headers.authorization;
  if (!authHeader) return null;
  if (!authHeader.startsWith('Bearer ')) return null;
  return authHeader.slice('Bearer '.length);
}

const server = createServer(async (req: IncomingMessage, res: ServerResponse) => {
  const url = req.url || '/';

  if (url === '/health') {
    return json(res, 200, { status: 'ok', service: 'zero-trust-auth' });
  }

  if (url === '/ready') {
    return json(res, 200, { ready: true });
  }

  if (url === '/verify' && req.method === 'GET') {
    const token = readBearer(req);
    if (!token) {
      return json(res, 401, { error: 'Missing bearer token' });
    }

    try {
      const metadata = {
        clientIP: (req.socket.remoteAddress || '').toString(),
        userAgent: (req.headers['user-agent'] || '').toString(),
        timestamp: Date.now(),
        clientCert: undefined,
      };
      const context = await auth.validateToken(token, metadata);
      return json(res, 200, { valid: true, context });
    } catch (e) {
      return json(res, 401, { valid: false, error: (e as Error).message });
    }
  }

  return json(res, 404, { error: 'Not found' });
});

server.listen(port, '0.0.0.0', () => {
  // Keep startup log compact for Cloud Run
  console.log(`zero-trust-auth listening on ${port}`);
});

process.on('SIGTERM', () => {
  auth.shutdown();
  server.close(() => process.exit(0));
});
