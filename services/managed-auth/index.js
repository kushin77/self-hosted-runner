#!/usr/bin/env node
// Minimal Express-based backend for RunnerCloud Managed Mode (Issue #8)
// - GitHub App OAuth flow skeleton
// - In-memory runner registry with per-second billing metrics
// - Simple API endpoints for portal integration
// Usage: node index.js (requires NODE_ENV=development for mock tokens)

import express from 'express';
import crypto from 'crypto';
import { setToken, getToken } from './lib/secretStore.js';

const app = express();
const port = process.env.PORT || 4000;

// simple in-memory stores for runners and usage
const runners = [];
const billingRecords = [];

app.use(express.json());

// redirect to GitHub OAuth endpoint (placeholder)
app.get('/oauth/start', (req, res) => {
  // in real world we would redirect to GitHub App installation flow
  const state = crypto.randomBytes(8).toString('hex');
  res.redirect(`https://github.com/login/oauth/authorize?client_id=${process.env.GITHUB_CLIENT_ID || 'fake'}&state=${state}`);
});

// callback from GitHub
app.get('/oauth/callback', async (req, res) => {
  const { code, state } = req.query;

  // here we would exchange code for access_token
  if (!code) {
    return res.status(400).send('missing code');
  }

  // simulate token creation
  const token = crypto.randomBytes(16).toString('hex');
  await setToken({ token, created: new Date().toISOString(), code });

  // respond with a small page instructing the user to create a runner
  res.send(`<html><body><h1>OAuth successful</h1><p>Your token: ${token}</p>` +
           `<p>Use POST /runners to provision your first managed runner.</p></body></html>`);
});

// list runners
app.get('/runners', (req, res) => {
  res.json(runners);
});

// provision a new runner (simplified)
app.post('/runners', (req, res) => {
  const { name, os = 'ubuntu-latest', pool = 'default', token } = req.body;
  if (!token) return res.status(401).json({ error: 'token required' });
  const owner = getToken(token);
  if (!owner) return res.status(403).json({ error: 'invalid token' });

  const id = `r-${runners.length + 1}`;
  const runner = { id, name: name || id, mode: 'managed', os, status: 'provisioning', pool, created: new Date().toISOString() };
  runners.push(runner);

  // simulate async provisioning
  setTimeout(() => {
    runner.status = 'running';
  }, 1000);

  res.status(201).json(runner);
});

// billing calculation endpoint
app.get('/billing', (req, res) => {
  // simple sum of per-second records for each runner
  const totalSeconds = billingRecords.reduce((sum, r) => sum + (r.seconds || 0), 0);
  const costPerSecond = parseFloat(process.env.COST_PER_SECOND || '0.0015');
  res.json({ totalSeconds, costPerSecond, estimate: (totalSeconds * costPerSecond).toFixed(2) });
});

// record usage (called by runner agents periodically)
app.post('/usage', (req, res) => {
  const { runnerId, seconds } = req.body;
  if (!runnerId || !seconds) return res.status(400).json({ error: 'runnerId and seconds required' });
  billingRecords.push({ runnerId, seconds, timestamp: new Date().toISOString() });
  res.status(204).end();
});

// healthcheck
app.get('/health', (req, res) => res.send('ok'));

app.listen(port, () => {
  console.log(`managed-auth service listening on port ${port}`);
});
