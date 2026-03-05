// TLS integration test: start metrics server with TLS and verify wss 'metrics:update'
const { startMetricsServer, stopMetricsServer } = require('../lib/metricsServer');
const ioClient = require('socket.io-client');
const selfsigned = require('selfsigned');

(async () => {
  const port = 9443;
  try {
    // generate short-lived self-signed cert for test
    const attrs = [{ name: 'commonName', value: 'localhost' }];
    const pems = selfsigned.generate(attrs, { days: 1 });

    process.env.SOCKET_TLS = 'true';
    // Provide inline PEMs to avoid writing secret files
    process.env.SOCKET_CERT = pems.cert;
    process.env.SOCKET_KEY = pems.private;
    process.env.SOCKET_AUTH_TOKEN = 'tls-secret';

    const server = await startMetricsServer(port);
    console.log(`[test] TLS metrics server started on ${port}`);

    // Connect using secure WebSocket (wss). Allow self-signed cert for test.
    const socket = ioClient(`https://localhost:${port}`, {
      path: '/socket.io',
      transports: ['polling'],
      auth: { token: 'tls-secret' },
      rejectUnauthorized: false,
    });

    const timeout = setTimeout(() => {
      console.error('[test] did not receive metrics:update within timeout');
      socket.close();
      stopMetricsServer();
      process.exit(2);
    }, 8000);

    socket.on('connect', () => {
      console.log('[test] socket connected', socket.id);
    });

    socket.on('metrics:update', (payload) => {
      console.log('[test] received metrics:update');
      clearTimeout(timeout);
      socket.close();
      stopMetricsServer();
      process.exit(0);
    });

    socket.on('connect_error', (err) => {
      console.error('[test] socket connect_error', err && err.message ? err.message : err);
    });
  } catch (err) {
    console.error('[test] error', err);
    process.exit(1);
  }
})();
