// Simple WebSocket load-test harness for portal mock-server
// Usage: node load_test.js [clients] [durationSeconds]

const WebSocket = require('ws');
const clients = parseInt(process.argv[2], 10) || 10;
const duration = parseInt(process.argv[3], 10) || 30; // seconds
const URL = process.env.URL || 'ws://localhost:3001/ws/events';

let totalReceived = 0;
let connections = [];

function startClient(i) {
  const ws = new WebSocket(URL);
  let received = 0;
  ws.on('open', () => {
    // console.log(`client ${i} open`);
  });
  ws.on('message', (data) => {
    received++;
    totalReceived++;
  });
  ws.on('error', (err) => {
    console.error(`client ${i} error`, err.message);
  });
  ws.on('close', () => {
    // console.log(`client ${i} closed`);
  });
  connections.push({ ws, receivedRef: () => received });
}

console.log(`Starting ${clients} clients for ${duration}s against ${URL}`);
for (let i = 0; i < clients; i++) startClient(i);

const start = Date.now();
const interval = setInterval(() => {
  const elapsed = Math.floor((Date.now() - start) / 1000);
  process.stdout.write(`\rElapsed: ${elapsed}s, total messages: ${totalReceived}`);
}, 1000);

setTimeout(() => {
  clearInterval(interval);
  // close
  connections.forEach(c => { try { c.ws.terminate(); } catch {} });
  console.log('\nTest complete');
  console.log(`Total messages received across ${clients} clients: ${totalReceived}`);
  process.exit(0);
}, duration * 1000);
