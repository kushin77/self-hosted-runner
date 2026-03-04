#!/usr/bin/env node
const http = require('http');
const { URL } = require('url');
const crypto = require('crypto');
const port = process.env.PORT || 4000;

const GITHUB_CLIENT_ID = process.env.GITHUB_CLIENT_ID || 'YOUR_CLIENT_ID';
const GITHUB_CLIENT_SECRET = process.env.GITHUB_CLIENT_SECRET || 'YOUR_CLIENT_SECRET';
const SIMULATE_OAUTH = process.env.SIMULATE_OAUTH === '1' || false;

function makeState() {
  return crypto.randomBytes(16).toString('hex');
}

const stateStore = new Set();
// In-memory token store for prototype. Replace with secure secrets manager (Vault/KMS) in production.
const tokenStore = [];

function jsonResponse(res, obj, status = 200) {
  const body = JSON.stringify(obj);
  res.writeHead(status, { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) });
  res.end(body);
}

const server = http.createServer(async (req, res) => {
  try {
    const reqUrl = new URL(req.url, `http://localhost:${port}`);
    if (reqUrl.pathname === '/') {
      res.writeHead(200, { 'Content-Type': 'text/plain' });
      return res.end('RunnerCloud Managed Auth Skeleton');
    }

    if (reqUrl.pathname === '/auth/github') {
      const state = makeState();
      stateStore.add(state);
      const params = new URLSearchParams({ client_id: GITHUB_CLIENT_ID, scope: 'repo' });
      const redirectUrl = `https://github.com/login/oauth/authorize?${params.toString()}&state=${state}`;
      res.writeHead(302, { Location: redirectUrl });
      return res.end();
    }

    if (reqUrl.pathname === '/auth/github/callback') {
      const code = reqUrl.searchParams.get('code');
      const state = reqUrl.searchParams.get('state');
      if (!code || !state) {
        return jsonResponse(res, { error: 'missing code or state' }, 400);
      }
      if (!stateStore.has(state)) {
        return jsonResponse(res, { error: 'invalid or expired state' }, 400);
      }
      stateStore.delete(state);
      if (SIMULATE_OAUTH) {
        // Store token in in-memory store (replace with secure secrets manager in prod)
        const token = 'simulated-token-123';
        tokenStore.push({ token, scope: 'repo', created_at: Date.now() });
        return jsonResponse(res, { access_token: token, scope: 'repo', token_type: 'bearer' });
      }
      // Exchange code for token with GitHub
      try {
        const tokenResp = await fetch('https://github.com/login/oauth/access_token', {
          method: 'POST',
          headers: { 'Accept': 'application/json', 'Content-Type': 'application/json' },
          body: JSON.stringify({ client_id: GITHUB_CLIENT_ID, client_secret: GITHUB_CLIENT_SECRET, code })
        });
        const tokenJson = await tokenResp.json();
        if (tokenJson.error) return jsonResponse(res, { error: tokenJson.error, description: tokenJson.error_description }, 400);
        return jsonResponse(res, tokenJson);
      } catch (err) {
        return jsonResponse(res, { error: 'token_exchange_failed', detail: String(err) }, 500);
      }
    }

    // Handle runner provisioning inside main handler to avoid listener ordering issues
    if (reqUrl.pathname === '/register-runner' && req.method === 'POST') {
      try {
        let body = '';
        for await (const chunk of req) body += chunk;
        const payload = body ? JSON.parse(body) : {};
        const { access_token, runner_meta } = payload;
        if (!access_token) return jsonResponse(res, { error: 'missing_token' }, 400);
        const found = tokenStore.find(t => t.token === access_token);
        if (!found) return jsonResponse(res, { error: 'invalid_token' }, 401);
        const runnerId = `runner-${Math.random().toString(36).slice(2,10)}`;
        return jsonResponse(res, { status: 'provisioned', runner_id: runnerId, meta: runner_meta || {} });
      } catch (e) {
        return jsonResponse(res, { error: 'bad_request', detail: String(e) }, 400);
      }
    }

    res.writeHead(404, { 'Content-Type': 'text/plain' });
    res.end('not found');
  } catch (err) {
    res.writeHead(500, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: String(err) }));
  }
});

// Start server
server.listen(port, () => console.log(`Managed Auth skeleton listening on ${port}`));

// Add a simple runner registration endpoint (provisioning stub)
// NOTE: We implement this by attaching a listener that inspects incoming requests and
// handles POST /register-runner. It uses the in-memory token store for validation.

const { once } = require('events');

// Monkey-patch: wrap the server's 'request' event to handle register-runner before other handlers
server.on('request', async (req, res) => {
  try {
    const reqUrl = new URL(req.url, `http://localhost:${port}`);
    if (reqUrl.pathname === '/register-runner' && req.method === 'POST') {
      let body = '';
      for await (const chunk of req) body += chunk;
      const payload = body ? JSON.parse(body) : {};
      const { access_token, runner_meta } = payload;
      if (!access_token) return jsonResponse(res, { error: 'missing_token' }, 400);
      const found = tokenStore.find(t => t.token === access_token);
      if (!found) return jsonResponse(res, { error: 'invalid_token' }, 401);
      const runnerId = `runner-${Math.random().toString(36).slice(2,10)}`;
      return jsonResponse(res, { status: 'provisioned', runner_id: runnerId, meta: runner_meta || {} });
    }
  } catch (err) {
    // fallthrough to main handler
  }
});
