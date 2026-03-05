"use strict";

/**
 * Metrics Server for Provisioner-Worker
 * Provides HTTP endpoints for Prometheus metrics and health checks
 */

const logger = require('./logger');
const metrics = require('./metrics');

let metricsServer = null;
let io = null;

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

      // Initialize Socket.IO for Phase 2 real-time migration
      const { Server } = require('socket.io');
      io = new Server(metricsServer, {
        cors: { origin: '*', methods: ['GET', 'POST'] },
        path: '/socket.io',
      });

      // middleware for authentication and rate limiting
      const connectionCounts = new Map(); // ip -> [timestamps]

      io.use((socket, next) => {
        const authToken = process.env.SOCKET_AUTH_TOKEN;
        if (authToken) {
          const provided = socket.handshake.auth?.token ||
            (socket.handshake.headers['authorization'] || '').split(' ')[1];
          if (provided !== authToken) {
            return next(new Error('unauthorized'));
          }
        }

        // simple per-IP rate limiter (max 10 connections per minute)
        const ip = socket.handshake.address || socket.request.socket.remoteAddress;
        const now = Date.now();
        const history = connectionCounts.get(ip) || [];
        const recent = history.filter((t) => now - t < 60000);
        recent.push(now);
        connectionCounts.set(ip, recent);
        if (recent.length > 10) {
          return next(new Error('rate limit exceeded'));
        }

        next();
      });

      io.on('connection', (socket) => {
        const log = require('./logger').child({ component: 'socket.io' });
        log.info('client connected', { id: socket.id });

        // Phase 2: send initial state upon connection
        socket.emit('metrics:update', metrics.getSummaryStats());

        socket.on('disconnect', () => {
          log.info('client disconnected', { id: socket.id });
        });
      });

      // Periodic broadcast for connected clients (Phase 2)
      setInterval(() => {
        if (io && io.engine.clientsCount > 0) {
          io.emit('metrics:update', metrics.getSummaryStats());
        }
      }, 5000);
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
