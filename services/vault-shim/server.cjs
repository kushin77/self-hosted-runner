const express = require('express');
const bodyParser = require('body-parser');

const app = express();
app.use(bodyParser.json());

// In-memory store for dev only
const store = Object.create(null);

// Config: dev token (default) and optional namespace behavior
const DEV_TOKEN = process.env.VAULT_DEV_TOKEN || 'root';

function authRequired(req, res, next) {
  // Accept token via X-Vault-Token or Authorization: Bearer <token>
  const headerToken = req.headers['x-vault-token'] || (() => {
    const auth = req.headers['authorization'];
    if (!auth) return undefined;
    const m = String(auth).match(/^Bearer\s+(.+)$/i);
    return m ? m[1] : undefined;
  })();

  if (!headerToken) return res.status(401).json({ error: 'missing token' });
  if (String(headerToken) !== String(DEV_TOKEN)) return res.status(403).json({ error: 'invalid token' });
  // attach effective namespace for handlers
  req.vaultNamespace = req.headers['x-vault-namespace'] || '';
  next();
}

app.get('/health', (req, res) => res.json({ ok: true }));

// Helper to apply namespace prefix to keys
function nsKey(ns, key) {
  if (!ns) return key;
  return `${ns}:${key}`;
}

// Emulate Vault KV v1 simple endpoints for dev
app.put('/v1/secret/:key', authRequired, (req, res) => {
  const key = req.params.key;
  const effectiveKey = nsKey(req.vaultNamespace, key);
  const value = req.body && req.body.value !== undefined ? req.body.value : req.body;
  if (value === undefined) return res.status(400).json({ error: 'missing value' });
  store[effectiveKey] = value;
  res.json({ ok: true, key: effectiveKey });
});

app.get('/v1/secret/:key', authRequired, (req, res) => {
  const key = req.params.key;
  const effectiveKey = nsKey(req.vaultNamespace, key);
  if (!(effectiveKey in store)) return res.status(404).json({ error: 'not found' });
  res.json({ value: store[effectiveKey] });
});

app.delete('/v1/secret/:key', authRequired, (req, res) => {
  const key = req.params.key;
  const effectiveKey = nsKey(req.vaultNamespace, key);
  delete store[effectiveKey];
  res.json({ ok: true });
});

const PORT = process.env.PORT || 8200;
app.listen(PORT, () => {
  console.log(`Vault dev shim listening at http://localhost:${PORT}`);
  console.log('Endpoints: PUT /v1/secret/:key  GET /v1/secret/:key');
  console.log('Auth: X-Vault-Token or Authorization: Bearer <token>');
  console.log('Namespace: X-Vault-Namespace (optional)');
});

module.exports = app;
