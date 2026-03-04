const WebSocket = require('ws');

const url = process.argv[2] || 'ws://localhost:3001/ws/events';
const clients = parseInt(process.argv[3], 10) || 10;
const duration = parseInt(process.argv[4], 10) || 10; // seconds

let totalMessages = 0;
let connected = 0;

function startClient(i) {
  return new Promise((resolve) => {
    const ws = new WebSocket(url);

    ws.on('open', () => {
      connected++;
    });

    ws.on('message', (msg) => {
      totalMessages++;
    });

    ws.on('close', () => {
      resolve();
    });

    ws.on('error', (err) => {
      resolve();
    });

    setTimeout(() => {
      try { ws.close(); } catch (e) { }
    }, duration * 1000);
  });
}

async function run() {
  const arr = [];
  for (let i = 0; i < clients; i++) arr.push(startClient(i));
  const start = Date.now();
  await Promise.all(arr);
  const elapsed = (Date.now() - start) / 1000;
  console.log(`Elapsed: ${elapsed}s, connected: ${connected}, total messages: ${totalMessages}`);
}

run();
