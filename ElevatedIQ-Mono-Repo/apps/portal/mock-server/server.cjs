const express = require('express');
const cors = require('cors');
const http = require('http');
const WebSocket = require('ws');
const data = require('./data.cjs');

const app = express();
app.use(cors());
app.use(express.json());

const PORT = process.env.PORT || 3001;

app.get('/api/runners', (req, res) => {
  res.json(data.runners);
});

app.get('/api/events', (req, res) => {
  res.json({ events: data.events, total: data.events.length, page: 1, pageSize: data.events.length });
});

app.get('/api/billing', (req, res) => {
  res.json(data.billing);
});

app.get('/api/cache', (req, res) => {
  res.json(data.cache);
});

app.get('/api/ai', (req, res) => {
  res.json(data.ai);
});

app.get('/api/agents', (req, res) => {
  res.json(data.agents);
});

const server = http.createServer(app);
const wss = new WebSocket.Server({ server, path: '/ws/events' });

function broadcastEvent(obj) {
  const msg = JSON.stringify(obj);
  wss.clients.forEach((c) => {
    if (c.readyState === WebSocket.OPEN) c.send(msg);
  });
}

wss.on('connection', (ws) => {
  ws.send(JSON.stringify({ type: 'snapshot', events: data.events.slice(-10) }));

  const ping = setInterval(() => {
    if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify({ type: 'ping', ts: Date.now() }));
  }, 15000);

  const interval = setInterval(() => {
    try {
      const evt = data.generateEvent();
      broadcastEvent({ type: 'event', event: evt });
    } catch (e) {
      const fallback = { id: Date.now().toString(), type: 'job_started', timestamp: Date.now(), message: 'simulated', severity: 'info' };
      broadcastEvent({ type: 'event', event: fallback });
    }
  }, Math.floor(Math.random() * 4000) + 1000);

  ws.on('close', () => {
    clearInterval(interval);
    clearInterval(ping);
  });
});

server.listen(PORT, () => {
  console.log(`Portal mock server listening at http://localhost:${PORT}`);
  console.log(`WebSocket events available at ws://localhost:${PORT}/ws/events`);
});
