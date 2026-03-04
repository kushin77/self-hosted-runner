const WebSocket = require('ws');

const url = process.argv[2] || 'ws://localhost:3001/ws/events';
const clients = Number(process.argv[3] || 3);
const duration = Number(process.argv[4] || 8);

let totalMessages = 0;
let connected = 0;

const conns = [];

for (let i = 0; i < clients; i++) {
  const ws = new WebSocket(url);
  conns.push(ws);
  ws.on('open', () => {
    connected++;
    // console.log('client', i, 'open');
  });
  ws.on('message', (m) => {
    totalMessages++;
  });
  ws.on('error', (e) => {
    console.error('ws error', e && e.message);
  });
}

setTimeout(() => {
  conns.forEach((c) => c.close());
  console.log('elapsed:', duration, 's, connected:', connected, 'total messages:', totalMessages);
  process.exit(0);
}, duration * 1000 + 500);
