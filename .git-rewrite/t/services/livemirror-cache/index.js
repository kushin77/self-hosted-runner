#!/usr/bin/env node
// LiveMirror Cache service skeleton
// Issue #9: expose cache layer metrics and allow warmup

import express from 'express';
const app = express();
const port = process.env.PORT || 4100;
app.use(express.json());

// in-memory cache layers
let layers = [
  { name: 'npm', type: 'npm', hitRate: 82, size: 14.2 * 1024 * 1024 * 1024, items: 18400, color: '#f1e05a' },
  { name: 'docker', type: 'docker', hitRate: 95, size: 47.3 * 1024 * 1024 * 1024, items: 240, color: '#239120' },
];

app.get('/cache', (req, res) => {
  res.json(layers.map((l) => ({
    name: l.name,
    type: l.type,
    hitRate: l.hitRate,
    sizeGB: (l.size / (1024*1024*1024)).toFixed(1) + 'GB',
    items: l.items,
  })));
});

app.post('/cache/warmup', (req, res) => {
  const { strategy } = req.body || {};
  let gain = 0;
  if (strategy === 'aggressive') gain = 10;
  else if (strategy === 'balanced') gain = 5;
  else gain = 1;

  layers = layers.map((l) => ({ ...l, hitRate: Math.min(100, l.hitRate + gain) }));
  res.json({ status: 'warming', addedGain: gain });
});

app.get('/health', (req, res) => res.send('ok'));

app.listen(port, () => console.log(`LiveMirror cache service listening on ${port}`));
