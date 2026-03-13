#!/usr/bin/env node
const express = require('express');
const bodyParser = require('body-parser');
const { v4: uuidv4 } = require('uuid');

const app = express();
app.use(bodyParser.json());

const PORT = process.env.PORT || 3000;
const HOST = process.env.WORKER_HOST || '';

if (!HOST) {
  console.error('ERROR: WORKER_HOST must be set for the mock server to bind to the worker node (no localhost).');
  console.error('Set WORKER_HOST environment variable to the worker node hostname or IP and restart.');
  process.exit(1);
}

const allowedTypes = ['aws','gcp','vault','github','azure'];

const db = {
  credentials: [],
  rotations: {},
  audit: [],
};

function authMiddleware(req, res, next) {
  if (req.path === '/health' || req.path.startsWith('/api/v1/auth/')) return next();
  const auth = req.headers['authorization'];
  if (!auth) return res.status(401).json({ message: 'Missing auth' });
  if (!auth.startsWith('Bearer ')) return res.status(401).json({ message: 'Invalid auth' });
  const token = auth.slice('Bearer '.length);
  if (!token.startsWith('mock_access_token')) return res.status(401).json({ message: 'Invalid token' });
  next();
}

app.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});

app.use('/api/v1', authMiddleware);

// Auth endpoints
app.post('/api/v1/auth/login', (req, res) => {
  const access_token = `mock_access_token_${Date.now()}`;
  const refresh_token = `mock_refresh_${Date.now()}`;
  res.json({ access_token, refresh_token, user: { id: 'test-user', name: 'Test User' } });
});

app.post('/api/v1/auth/validate', (req, res) => {
  res.json({ valid: true, expiresAt: new Date(Date.now() + 3600*1000).toISOString() });
});

app.post('/api/v1/auth/refresh', (req, res) => {
  const access_token = `mock_access_token_${Date.now()}`;
  res.json({ access_token });
});

// Credentials
app.get('/api/v1/credentials', (req, res) => {
  let { type, limit = 20, offset = 0 } = req.query;
  limit = Number(limit);
  offset = Number(offset);
  let creds = db.credentials.filter(c => !c.deleted);
  if (type) creds = creds.filter(c => c.type === type);
  const total = creds.length;
  const slice = creds.slice(offset, offset + limit);
  res.json({ credentials: slice, total });
});

app.post('/api/v1/credentials', (req, res) => {
  const { name, type, secret, metadata } = req.body;
  if (!name || !type || !secret) return res.status(400).json({ message: 'Missing required fields' });
  if (!allowedTypes.includes(type)) return res.status(400).json({ message: 'Invalid type' });
  if (db.credentials.find(c => c.name === name && !c.deleted)) return res.status(409).json({ message: 'Duplicate name' });
  const id = uuidv4();
  const now = new Date().toISOString();
  const cred = { id, name, type, secret, metadata: metadata || {}, created_at: now, updated_at: now, last_rotated: null, rotation_status: 'none', deleted: false };
  db.credentials.push(cred);
  // audit
  db.audit.push({ id: uuidv4(), resource_type: 'credential', resource_id: id, action: 'create', actor: 'mock', created_at: now, details: { name } });
  res.status(201).json({ credential: cred });
});

app.get('/api/v1/credentials/:id', (req, res) => {
  const cred = db.credentials.find(c => c.id === req.params.id && !c.deleted);
  if (!cred) return res.status(404).json({ message: 'Not found' });
  res.json({ credential: cred });
});

app.put('/api/v1/credentials/:id', (req, res) => {
  const cred = db.credentials.find(c => c.id === req.params.id && !c.deleted);
  if (!cred) return res.status(404).json({ message: 'Not found' });
  const { name, metadata, rotationPolicy } = req.body;
  if (name) cred.name = name;
  if (metadata) cred.metadata = metadata;
  cred.updated_at = new Date().toISOString();
  db.audit.push({ id: uuidv4(), resource_type: 'credential', resource_id: cred.id, action: 'update', actor: 'mock', created_at: cred.updated_at, details: { name } });
  res.json({ credential: cred });
});

app.delete('/api/v1/credentials/:id', (req, res) => {
  const cred = db.credentials.find(c => c.id === req.params.id && !c.deleted);
  if (!cred) return res.status(404).json({ message: 'Not found' });
  cred.deleted = true;
  const now = new Date().toISOString();
  db.audit.push({ id: uuidv4(), resource_type: 'credential', resource_id: cred.id, action: 'delete', actor: 'mock', created_at: now, details: {} });
  res.json({ message: 'deleted' });
});

app.post('/api/v1/credentials/:id/rotate', (req, res) => {
  const cred = db.credentials.find(c => c.id === req.params.id && !c.deleted);
  if (!cred) return res.status(404).json({ message: 'Not found' });
  const rotationId = uuidv4();
  const now = new Date().toISOString();
  db.rotations[cred.id] = db.rotations[cred.id] || [];
  db.rotations[cred.id].push({ rotationId, scheduledAt: now, status: 'completed', reason: req.body?.reason || null });
  cred.last_rotated = now;
  cred.rotation_status = 'completed';
  db.audit.push({ id: uuidv4(), resource_type: 'credential', resource_id: cred.id, action: 'rotate', actor: 'mock', created_at: now, details: { rotationId } });
  res.json({ rotationId, status: 'completed', scheduledAt: now });
});

app.get('/api/v1/credentials/:id/rotations', (req, res) => {
  const rotations = db.rotations[req.params.id] || [];
  res.json({ rotations, total: rotations.length });
});

// Audit endpoints
app.get('/api/v1/audit', (req, res) => {
  let { resource_type, action, from_date, to_date, limit = 50, offset = 0 } = req.query;
  limit = Number(limit);
  offset = Number(offset);
  let entries = db.audit.slice().reverse();
  if (resource_type) entries = entries.filter(e => e.resource_type === resource_type);
  if (action) entries = entries.filter(e => e.action === action);
  if (from_date) entries = entries.filter(e => new Date(e.created_at) >= new Date(from_date));
  if (to_date) entries = entries.filter(e => new Date(e.created_at) <= new Date(to_date));
  const total = entries.length;
  const slice = entries.slice(offset, offset + limit);
  res.json({ entries: slice, total, verified: true });
});

app.post('/api/v1/audit/verify', (req, res) => {
  res.json({ isValid: true, entriesChecked: db.audit.length });
});

// Start server binding to worker host only
app.listen(PORT, HOST, () => {
  console.log(`Mock API server listening on http://${HOST}:${PORT}`);
});
#!/usr/bin/env node
const express = require('express');
const bodyParser = require('body-parser');
const { v4: uuidv4 } = require('uuid');

const app = express();
app.use(bodyParser.json());

const PORT = process.env.PORT || 3000;
const HOST = process.env.WORKER_HOST || '';

if (!HOST) {
  console.error('ERROR: WORKER_HOST must be set for the mock server to bind to the worker node (no localhost).');
  console.error('Set WORKER_HOST environment variable to the worker node hostname or IP and restart.');
  process.exit(1);
}

const allowedTypes = ['aws','gcp','vault','github','azure'];

const db = {
  credentials: [],
  rotations: {},
  audit: [],
};

function authMiddleware(req, res, next) {
  if (req.path === '/health' || req.path.startsWith('/api/v1/auth/')) return next();
  const auth = req.headers['authorization'];
  if (!auth) return res.status(401).json({ message: 'Missing auth' });
  if (!auth.startsWith('Bearer ')) return res.status(401).json({ message: 'Invalid auth' });
  const token = auth.slice('Bearer '.length);
  if (!token.startsWith('mock_access_token')) return res.status(401).json({ message: 'Invalid token' });
  next();
}

app.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});

app.use('/api/v1', authMiddleware);

// Auth endpoints
app.post('/api/v1/auth/login', (req, res) => {
  const access_token = `mock_access_token_${Date.now()}`;
  const refresh_token = `mock_refresh_${Date.now()}`;
  res.json({ access_token, refresh_token, user: { id: 'test-user', name: 'Test User' } });
});

app.post('/api/v1/auth/validate', (req, res) => {
  res.json({ valid: true, expiresAt: new Date(Date.now() + 3600*1000).toISOString() });
});

app.post('/api/v1/auth/refresh', (req, res) => {
  const access_token = `mock_access_token_${Date.now()}`;
  res.json({ access_token });
});

// Credentials
app.get('/api/v1/credentials', (req, res) => {
  let { type, limit = 20, offset = 0 } = req.query;
  limit = Number(limit);
  offset = Number(offset);
  let creds = db.credentials.filter(c => !c.deleted);
  if (type) creds = creds.filter(c => c.type === type);
  const total = creds.length;
  const slice = creds.slice(offset, offset + limit);
  res.json({ credentials: slice, total });
});

app.post('/api/v1/credentials', (req, res) => {
  const { name, type, secret, metadata } = req.body;
  if (!name || !type || !secret) return res.status(400).json({ message: 'Missing required fields' });
  if (!allowedTypes.includes(type)) return res.status(400).json({ message: 'Invalid type' });
  if (db.credentials.find(c => c.name === name && !c.deleted)) return res.status(409).json({ message: 'Duplicate name' });
  const id = uuidv4();
  const now = new Date().toISOString();
  const cred = { id, name, type, secret, metadata: metadata || {}, created_at: now, updated_at: now, last_rotated: null, rotation_status: 'none', deleted: false };
  db.credentials.push(cred);
  // audit
  db.audit.push({ id: uuidv4(), resource_type: 'credential', resource_id: id, action: 'create', actor: 'mock', created_at: now, details: { name } });
  res.status(201).json({ credential: cred });
});

app.get('/api/v1/credentials/:id', (req, res) => {
  const cred = db.credentials.find(c => c.id === req.params.id && !c.deleted);
  if (!cred) return res.status(404).json({ message: 'Not found' });
  res.json({ credential: cred });
});

app.put('/api/v1/credentials/:id', (req, res) => {
  const cred = db.credentials.find(c => c.id === req.params.id && !c.deleted);
  if (!cred) return res.status(404).json({ message: 'Not found' });
  const { name, metadata, rotationPolicy } = req.body;
  if (name) cred.name = name;
  if (metadata) cred.metadata = metadata;
  cred.updated_at = new Date().toISOString();
  db.audit.push({ id: uuidv4(), resource_type: 'credential', resource_id: cred.id, action: 'update', actor: 'mock', created_at: cred.updated_at, details: { name } });
  res.json({ credential: cred });
});

app.delete('/api/v1/credentials/:id', (req, res) => {
  const cred = db.credentials.find(c => c.id === req.params.id && !c.deleted);
  if (!cred) return res.status(404).json({ message: 'Not found' });
  cred.deleted = true;
  const now = new Date().toISOString();
  db.audit.push({ id: uuidv4(), resource_type: 'credential', resource_id: cred.id, action: 'delete', actor: 'mock', created_at: now, details: {} });
  res.json({ message: 'deleted' });
});

app.post('/api/v1/credentials/:id/rotate', (req, res) => {
  const cred = db.credentials.find(c => c.id === req.params.id && !c.deleted);
  if (!cred) return res.status(404).json({ message: 'Not found' });
  const rotationId = uuidv4();
  const now = new Date().toISOString();
  db.rotations[cred.id] = db.rotations[cred.id] || [];
  db.rotations[cred.id].push({ rotationId, scheduledAt: now, status: 'completed', reason: req.body?.reason || null });
  cred.last_rotated = now;
  cred.rotation_status = 'completed';
  db.audit.push({ id: uuidv4(), resource_type: 'credential', resource_id: cred.id, action: 'rotate', actor: 'mock', created_at: now, details: { rotationId } });
  res.json({ rotationId, status: 'completed', scheduledAt: now });
});

app.get('/api/v1/credentials/:id/rotations', (req, res) => {
  const rotations = db.rotations[req.params.id] || [];
  res.json({ rotations, total: rotations.length });
});

// Audit endpoints
app.get('/api/v1/audit', (req, res) => {
  let { resource_type, action, from_date, to_date, limit = 50, offset = 0 } = req.query;
  limit = Number(limit);
  offset = Number(offset);
  let entries = db.audit.slice().reverse();
  if (resource_type) entries = entries.filter(e => e.resource_type === resource_type);
  if (action) entries = entries.filter(e => e.action === action);
  if (from_date) entries = entries.filter(e => new Date(e.created_at) >= new Date(from_date));
  if (to_date) entries = entries.filter(e => new Date(e.created_at) <= new Date(to_date));
  const total = entries.length;
  const slice = entries.slice(offset, offset + limit);
  res.json({ entries: slice, total, verified: true });
});

app.post('/api/v1/audit/verify', (req, res) => {
  res.json({ isValid: true, entriesChecked: db.audit.length });
});

// Start server binding to worker host only
app.listen(PORT, HOST, () => {
  console.log(`Mock API server listening on http://${HOST}:${PORT}`);
});
