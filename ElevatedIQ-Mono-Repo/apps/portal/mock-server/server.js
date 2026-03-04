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

  // Simulate new events every 1-5 seconds using generator from data.js
  const interval = setInterval(() => {
    try {
      const evt = data.generateEvent();
      broadcastEvent({ type: 'event', event: evt });
    } catch (e) {
      // fallback
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
