// Minimal WebSocket adapter skeleton for Portal

export interface WebSocketAdapterOptions {
  path?: string; // mount path for ws server
}

import type { Server as HttpServer } from 'http';

export default function WebSocketAdapter(opts: WebSocketAdapterOptions = {}) {
  const path = opts.path || '/ws';

  return {
    name: 'websocket',
    mountPath: path,
    // initialize server (provide express app or http server)
    async init(server: HttpServer) {
      void server;
      // Example: attach ws server here
      // const WebSocket = require('ws');
      // const wss = new WebSocket.Server({ server, path });
      // wss.on('connection', (socket) => { /* ... */ });
    },
    async handleMessage(client: any, message: any) {
      void client;
      void message;
      // route inbound message to portal runtime
    },
    async shutdown() {
      // cleanup
    },
  };
}
