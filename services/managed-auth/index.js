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
        return jsonResponse(res, { access_token: 'simulated-token-123', scope: 'repo', token_type: 'bearer' });
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

    res.writeHead(404, { 'Content-Type': 'text/plain' });
    res.end('not found');
  } catch (err) {
    res.writeHead(500, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: String(err) }));
  }
});

server.listen(port, () => console.log(`Managed Auth skeleton listening on ${port}`));
