const express = require('express');
const cors = require('cors');
const http = require('http');
const WebSocket = require('ws');
const data = require('./data');

const app = express();
app.use(cors());
app.use(express.json());

const PORT = process.env.PORT || 3001;

app.get('/api/runners', (req, res) => {
  res.json(data.runners);
});

app.get('/api/events', (req, res) => {
  res.json(data.events);
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

// Create HTTP server and attach WebSocket server for event streaming
const server = http.createServer(app);
const wss = new WebSocket.Server({ server, path: '/ws/events' });

// Broadcast helper
function broadcastEvent(obj) {
  const msg = JSON.stringify(obj);
  wss.clients.forEach((c) => {
    if (c.readyState === WebSocket.OPEN) c.send(msg);
  });
}

// When a client connects, send initial events and then periodic simulated events
wss.on('connection', (ws) => {
  // send existing recent events
  ws.send(JSON.stringify({ type: 'snapshot', events: data.events.slice(-10) }));

  // heartbeat / ping
  const ping = setInterval(() => {
    if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify({ type: 'ping', ts: Date.now() }));
  }, 15000);

  // Simulate new events every 3-8 seconds
  const interval = setInterval(() => {
    const evt = {
      time: new Date().toISOString(),
      type: Math.random() > 0.8 ? 'blocked' : Math.random() > 0.5 ? 'sbom' : 'allowed',
      severity: Math.random() > 0.9 ? 'critical' : Math.random() > 0.7 ? 'high' : Math.random() > 0.4 ? 'warn' : 'info',
      message: 'Simulated eBPF event ' + Math.floor(Math.random() * 1000),
      details: 'source: rc-' + Math.random().toString(36).slice(2, 8),
    };
    broadcastEvent({ type: 'event', event: evt });
  }, Math.floor(Math.random() * 5000) + 3000);

  ws.on('close', () => {
    clearInterval(interval);
    clearInterval(ping);
  });
});

server.listen(PORT, () => {
  console.log(`Portal mock server listening at http://localhost:${PORT}`);
  console.log(`WebSocket events available at ws://localhost:${PORT}/ws/events`);
});
