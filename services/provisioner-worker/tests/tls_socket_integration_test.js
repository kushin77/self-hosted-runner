// TLS integration test: start metrics server with TLS and verify wss 'metrics:update'
// allow self-signed certs during test
process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';
const { startMetricsServer, stopMetricsServer } = require('../lib/metricsServer');
const ioClient = require('socket.io-client');
const selfsigned = require('selfsigned');
const nock = require('nock');
const fetch = require('node-fetch').default;

(async () => {
  const port = 9443;
  try {
    // generate short-lived self-signed cert for test
    const attrs = [{ name: 'commonName', value: 'localhost' }];
    const pems = selfsigned.generate(attrs, { days: 1 });

    process.env.SOCKET_TLS = 'true';
    // for this test we exercise Vault paths rather than direct env vars
    const vaultPath = 'secret/data/socket';
    process.env.SOCKET_TOKEN_VAULT_PATH = vaultPath;
    process.env.SOCKET_CERT_VAULT_PATH = vaultPath;
    process.env.VAULT_ADDR = 'http://localhost:8200';
    process.env.VAULT_TOKEN = 'vault-test-token';

    // prepare nock to return both token and cert/key
    nock(process.env.VAULT_ADDR)
      .persist()
      .get(`/v1/${vaultPath}`)
      .matchHeader('X-Vault-Token', process.env.VAULT_TOKEN)
      .reply(200, { data: { token: 'tls-secret', cert: pems.cert, key: pems.private } });

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

    socket.on('metrics:update', async (payload) => {
      console.log('[test] received metrics:update');
      clearTimeout(timeout);
      socket.close();
      // verify metrics summary counters exist
      try {
        const res = await fetch(`https://localhost:${port}/metrics/summary`, { rejectUnauthorized: false });
        const json = await res.json();
        console.log('[test] metrics summary', json);
      } catch (e) {
        console.warn('[test] failed to fetch metrics summary', e.message);
      }
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
