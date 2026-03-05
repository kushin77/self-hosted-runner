"use strict";

// HTTP server to expose metrics and health endpoints for managed-auth

const express = require('express');
const logger = require('./logger.cjs');
const metrics = require('./metrics.cjs');

const app = express();
const port = process.env.METRICS_PORT || 9091; // avoid clash with main service

app.get('/metrics', (req, res) => {
  res.set('Content-Type', 'text/plain; version=0.0.4');
  res.send(metrics.getPrometheusMetrics());
});

app.get('/health', (req, res) => {
  res.send('ok');
});

app.get('/ready', (req, res) => {
  // readiness probe: always ready for simplicity
  res.send('ready');
});

app.get('/alive', (req, res) => {
  res.send('alive');
});

function start() {
  app.listen(port, () => {
    logger.info('metrics server listening', { port });
  });
}

module.exports = { start };
