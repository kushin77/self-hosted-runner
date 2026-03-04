const express = require('express');
const bodyParser = require('body-parser');

const app = express();
app.use(bodyParser.json());

// In-memory store for dev only
const store = Object.create(null);

app.get('/health', (req, res) => res.json({ ok: true }));

// Emulate Vault KV v1 simple endpoints for dev
app.put('/v1/secret/:key', (req, res) => {
  const key = req.params.key;
  const value = req.body && req.body.value !== undefined ? req.body.value : req.body;
  if (value === undefined) return res.status(400).json({ error: 'missing value' });
  store[key] = value;
  res.json({ ok: true, key });
});

app.get('/v1/secret/:key', (req, res) => {
  const key = req.params.key;
  if (!(key in store)) return res.status(404).json({ error: 'not found' });
  res.json({ value: store[key] });
});

app.delete('/v1/secret/:key', (req, res) => {
  const key = req.params.key;
  delete store[key];
  res.json({ ok: true });
});

const PORT = process.env.PORT || 8200;
app.listen(PORT, () => {
  console.log(`Vault dev shim listening at http://localhost:${PORT}`);
  console.log('Endpoints: PUT /v1/secret/:key  GET /v1/secret/:key');
});

module.exports = app;
