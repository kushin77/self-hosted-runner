"use strict";

/**
 * Metrics Server for Provisioner-Worker
 * Provides HTTP endpoints for Prometheus metrics and health checks
 */

const logger = require('./logger');
const metrics = require('./metrics');

let metricsServer = null;

/**
 * Start metrics HTTP server
 * @param {number} port - Port to listen on (default: 9090)
 * @param {object} app - Optional existing Express app
 * @returns {http.Server} - HTTP server instance
 */
async function startMetricsServer(port = 9090, app = null) {
  try {
    const useExisting = app !== null;
    const express = require('express');
    const finalApp = useExisting ? app : express();
    
    // Prometheus metrics endpoint
    finalApp.get('/metrics', (req, res) => {
      res.set('Content-Type', 'text/plain; version=0.0.4; charset=utf-8');
      res.send(metrics.getPrometheusMetrics());
    });
    
    // Health check endpoint
    finalApp.get('/health', (req, res) => {
      const stats = metrics.getSummaryStats();
      res.json({
        status: 'operational',
        timestamp: new Date().toISOString(),
        metrics: stats,
      });
    });
    
    // Metrics summary endpoint (JSON format)
    finalApp.get('/metrics/summary', (req, res) => {
      res.json(metrics.getSummaryStats());
    });
    
    // Readiness check endpoint
    finalApp.get('/ready', (req, res) => {
      const stats = metrics.getSummaryStats();
      const isReady = stats.health.jobstoreOperational && metrics.metrics.loop_running;
      
      if (isReady) {
        res.status(200).json({ ready: true });
      } else {
        res.status(503).json({ 
          ready: false, 
          reason: !metrics.metrics.loop_running ? 'loop_not_running' : 'jobstore_error',
        });
      }
    });
    
    // Liveness check endpoint
    finalApp.get('/alive', (req, res) => {
      res.json({ alive: true });
    });
    
    // Only start server if not using existing Express app
    if (!useExisting) {
      metricsServer = finalApp.listen(port, '0.0.0.0', () => {
        const log = require('./logger').child({component:'metricsServer'});
      log.info('server listening', {url:`http://0.0.0.0:${port}`});
      log.info('endpoint','/metrics Prometheus format');
      log.info('endpoint','/health health status');
      log.info('endpoint','/metrics/summary JSON metrics');
      log.info('endpoint','/ready readiness check');
      log.info('endpoint','/alive liveness check');
      });
    }
    
    return metricsServer || finalApp;
  } catch (error) {
    console.error('[metrics] Failed to start metrics server:', error);
    throw error;
  }
}

/**
 * Stop metrics server
 */
function stopMetricsServer() {
  if (metricsServer) {
    metricsServer.close(() => {
      require('./logger').info('metrics server stopped');
    });
    metricsServer = null;
  }
}

/**
 * Get current metrics summary
 * @returns {object} - Summary statistics
 */
function getSummary() {
  return metrics.getSummaryStats();
}

module.exports = {
  startMetricsServer,
  stopMetricsServer,
  getSummary,
  metrics,
};
