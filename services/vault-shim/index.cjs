"use strict";

/**
 * Vault shim service index - provides a minimal HTTP API for secret retrieval.
 * Structured logging added for Phase P3.2 observability.
 */

const express = require('express');
const bodyParser = require('body-parser');
const logger = require('./lib/logger');
const metrics = require('./lib/metrics');
const metricsServer = require('./lib/metricsServer');

const app = express();
const port = process.env.PORT || 4200;

if (process.env.ENABLE_METRICS !== 'false') {
  metricsServer.start();
}

// middleware
app.use(bodyParser.json());
app.use((req, res, next) => {
  req.correlation_id = req.headers['x-correlation-id'] || logger.genCorrelationId();
  req.log = logger.child({ correlation_id: req.correlation_id });
  req.log.info('incoming request', { path: req.path, method: req.method });

  const start = Date.now();
  metrics.incActive();
  res.once('finish', () => {
    metrics.decActive();
    const ms = Date.now() - start;
    const status = res.statusCode < 400 ? 'success' : 'failure';
    metrics.recordRequest(status, ms);
  });

  next();
});

// health
app.get('/health', (req, res) => {
  req.log.info('health check');
  res.send('ok');
});

// placeholder secret fetch
app.post('/secret', (req, res) => {
  const { key } = req.body;
  req.log.info('secret requested', { key });
  // In P2 this would proxy to Vault; here just echo key
  res.json({ value: `secret-for-${key}` });
});

app.listen(port, () => {
  logger.info('vault-shim service listening', { port });
});
