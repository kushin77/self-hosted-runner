// Simple integration test: start metrics server and verify socket.io 'metrics:update'
const { startMetricsServer, stopMetricsServer } = require('../lib/metricsServer');
const ioClient = require('socket.io-client');

(async () => {
  const port = 9090;
  try {
    // require auth token for this test
    process.env.SOCKET_AUTH_TOKEN = 'secret';

    const server = await startMetricsServer(port);
    console.log(`[test] metrics server started on ${port}`);

    // first try connecting without token (should fail)
    const badSocket = ioClient(`http://localhost:${port}`, {
      path: '/socket.io',
      transports: ['polling'],
      timeout: 2000,
    });

    badSocket.on('connect_error', (err) => {
      console.log('[test] expected unauthorized error', err.message || err);
      badSocket.close();
    });

    // Use polling transport with auth token
    const socket = ioClient(`http://localhost:${port}`, {
      path: '/socket.io',
      transports: ['polling'],
      auth: { token: 'secret' },
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
      // stop server gracefully
      stopMetricsServer();
      process.exit(0);
    });

    socket.on('connect_error', (err) => {
      console.error('[test] socket connect_error', err.message || err);
    });
  } catch (err) {
    console.error('[test] error', err);
    process.exit(1);
  }
})();
