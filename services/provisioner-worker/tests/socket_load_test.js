#!/usr/bin/env node
// Simple load tester for the provisioner-worker socket endpoint.
// Usage: node tests/socket_load_test.js [port] [clients]
const ioClient = require('socket.io-client');

const port = process.argv[2] ? parseInt(process.argv[2],10) : 9090;
const clients = process.argv[3] ? parseInt(process.argv[3],10) : 100;

console.log(`starting load test: ${clients} clients to ws://localhost:${port}`);

let connected = 0;
let disconnected = 0;
let updates = 0;

const sockets = [];
for (let i = 0; i < clients; i++) {
  const socket = ioClient(`http://localhost:${port}`, {
    path: '/socket.io',
    transports: ['polling'],
    auth: { token: process.env.SOCKET_AUTH_TOKEN || 'secret' },
  });
  sockets.push(socket);
  socket.on('connect', () => {
    connected++;
  });
  socket.on('disconnect', () => {
    disconnected++;
  });
  socket.on('metrics:update', () => {
    updates++;
  });
  socket.on('connect_error', (err) => {
    console.error('connect_error', err.message || err);
  });
}

// run for 15 seconds then report
setTimeout(() => {
  console.log(`connected: ${connected}/${clients}, disconnected: ${disconnected}, updates received: ${updates}`);
  sockets.forEach(s => s.close());
  process.exit(0);
}, 15000);
