"use strict";

const express = require('express');
const logger = require('./logger');
const metrics = require('./metrics');

const app = express();
const port = process.env.METRICS_PORT || 9092;

app.get('/metrics', (req, res) => {
  res.set('Content-Type', 'text/plain; version=0.0.4');
  res.send(metrics.getPrometheusMetrics());
});
app.get('/health', (req, res) => res.send('ok'));
app.get('/ready', (req, res) => res.send('ready'));
app.get('/alive', (req, res) => res.send('alive'));

function start() {
  app.listen(port, () => {
    logger.info('vault-shim metrics server listening', { port });
  });
}

module.exports = { start };
