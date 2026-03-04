#!/usr/bin/env node
const express = require('express');
const { URL } = require('url');
const crypto = require('crypto');
const app = express();
const port = process.env.PORT || 4000;

const GITHUB_CLIENT_ID = process.env.GITHUB_CLIENT_ID || 'YOUR_CLIENT_ID';
const GITHUB_CLIENT_SECRET = process.env.GITHUB_CLIENT_SECRET || 'YOUR_CLIENT_SECRET';
const SIMULATE_OAUTH = process.env.SIMULATE_OAUTH === '1' || false;

function makeState() {
  return crypto.randomBytes(16).toString('hex');
}

// In-memory map for states for the skeleton. Replace with persistent store in prod.
const stateStore = new Set();

app.get('/', (req, res) => res.send('RunnerCloud Managed Auth Skeleton'));

// Redirect user to GitHub OAuth with a generated state.
app.get('/auth/github', (req, res) => {
  const state = makeState();
  stateStore.add(state);
  const params = new URLSearchParams({
    client_id: GITHUB_CLIENT_ID,
    scope: 'repo'
  });
  const redirectUrl = `https://github.com/login/oauth/authorize?${params.toString()}&state=${state}`;
  res.redirect(redirectUrl);
});

// OAuth callback: validate state, exchange code for token (or simulate)
app.get('/auth/github/callback', async (req, res) => {
  const { code, state } = req.query;
  if (!code || !state) {
    return res.status(400).json({ error: 'missing code or state' });
  }
  if (!stateStore.has(state)) {
    return res.status(400).json({ error: 'invalid or expired state' });
  }
  // Consume state
  stateStore.delete(state);

  if (SIMULATE_OAUTH) {
    // Return a simulated token for local dev and CI smoke tests
    return res.json({ access_token: 'simulated-token-123', scope: 'repo', token_type: 'bearer' });
  }

  // Exchange code for token with GitHub
  try {
    const tokenResp = await fetch('https://github.com/login/oauth/access_token', {
      method: 'POST',
      headers: { 'Accept': 'application/json', 'Content-Type': 'application/json' },
      body: JSON.stringify({ client_id: GITHUB_CLIENT_ID, client_secret: GITHUB_CLIENT_SECRET, code })
    });
    const tokenJson = await tokenResp.json();
    if (tokenJson.error) return res.status(400).json({ error: tokenJson.error, description: tokenJson.error_description });
    // Here you'd persist token and create runner registration flow
    return res.json(tokenJson);
  } catch (err) {
    return res.status(500).json({ error: 'token_exchange_failed', detail: String(err) });
  }
});

app.listen(port, () => console.log(`Managed Auth skeleton listening on ${port}`));
