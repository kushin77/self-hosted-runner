#!/usr/bin/env node
// Minimal Express-based backend for RunnerCloud Managed Mode (Issue #8)
// - GitHub App OAuth flow skeleton
// - In-memory runner registry with per-second billing metrics
// - Simple API endpoints for portal integration
// Usage: node index.js (requires NODE_ENV=development for mock tokens)

import express from 'express';
import crypto from 'crypto';
import { createRequire } from 'module';
const require = createRequire(import.meta.url);
const { setToken, getToken } = require('./lib/secretStore.cjs');
// logger is implemented in CommonJS (renamed to logger.cjs)
const logger = require('./lib/logger.cjs');
const metrics = require('./lib/metrics.cjs');
const metricsServer = require('./lib/metricsServer.cjs');
const otel = require('./lib/otel.cjs');

// optional OpenTelemetry
otel.init();

const app = express();
const port = process.env.PORT || 4000;

// start metrics listener separately
if (process.env.ENABLE_METRICS !== 'false') {
  metricsServer.start();
}

// each request can have a correlation id header; fallback to generated
app.use((req, res, next) => {
  req.correlation_id = req.headers['x-correlation-id'] || logger.genCorrelationId();
  req.log = logger.child({ correlation_id: req.correlation_id });

  // OTEL tracing
  const tracer = otel.getTracer();
  const span = tracer ? tracer.startSpan('http_request', { attributes: { path: req.path, method: req.method } }) : null;
  if (span) req.span = span;
  // metrics instrumentation: track active requests and latency
  const start = Date.now();
  metrics.incActive();
  res.once('finish', () => {
    metrics.decActive();
    const ms = Date.now() - start;
    const status = res.statusCode < 400 ? 'success' : 'failure';
    metrics.recordRequest(status, ms);
    if (span) {
      span.setAttribute('http.status_code', res.statusCode);
      span.addEvent('response_sent', { duration_ms: ms });
      span.end();
    }
  });

  next();
});

// simple in-memory stores for runners and usage
const runners = [];
const billingRecords = [];
const heartbeats = {}; // track heartbeat timestamp per runner
const auditLogs = []; // audit trail

app.use(express.json());

// redirect to GitHub OAuth endpoint (placeholder)
app.get('/oauth/start', (req, res) => {
  const log = logger.child({ correlation_id: req.correlation_id });
  log.info('oauth/start invoked');
  // in real world we would redirect to GitHub App installation flow
  const state = crypto.randomBytes(8).toString('hex');
  res.redirect(`https://github.com/login/oauth/authorize?client_id=${process.env.GITHUB_CLIENT_ID || 'fake'}&state=${state}`);
});

// callback from GitHub
app.get('/oauth/callback', async (req, res) => {
  const { code, state } = req.query;

  // here we would exchange code for access_token
  if (!code) {
    return res.status(400).send('missing code');
  }

  // simulate token creation
  const token = crypto.randomBytes(16).toString('hex');
  await setToken({ token, created: new Date().toISOString(), code });

  // respond with a small page instructing the user to create a runner
  res.send(`<html><body><h1>OAuth successful</h1><p>Your token: ${token}</p>` +
           `<p>Use POST /runners to provision your first managed runner.</p></body></html>`);
});

// list runners
app.get('/runners', (req, res) => {
  res.json(runners);
});

// provision a new runner (simplified)
app.post('/runners', (req, res) => {
  const { name, os = 'ubuntu-latest', pool = 'default', token } = req.body;
  if (!token) return res.status(401).json({ error: 'token required' });
  const owner = getToken(token);
  if (!owner) return res.status(403).json({ error: 'invalid token' });

  const id = `r-${runners.length + 1}`;
  const runner = { id, name: name || id, mode: 'managed', os, status: 'provisioning', pool, created: new Date().toISOString() };
  runners.push(runner);

  // simulate async provisioning
  setTimeout(() => {
    runner.status = 'running';
  }, 1000);

  res.status(201).json(runner);
});

// billing calculation endpoint
app.get('/billing', (req, res) => {
  // simple sum of per-second records for each runner
  const totalSeconds = billingRecords.reduce((sum, r) => sum + (r.seconds || 0), 0);
  const costPerSecond = parseFloat(process.env.COST_PER_SECOND || '0.0015');
  res.json({ totalSeconds, costPerSecond, estimate: (totalSeconds * costPerSecond).toFixed(2) });
});

// instant deploy orchestration (UI uses this to kick off mode selection)
app.post('/instant-deploy', (req, res) => {
  const { mode } = req.body || {};
  if (!mode) return res.status(400).json({ error: 'mode required' });
  // In a real system we would route to appropriate service (managed, byoc, onprem)
  // For now we return a simple success token and a fake runner URL
  const deployId = crypto.randomBytes(8).toString('hex');
  res.json({ deployId, mode, status: 'initiated', runnerUrl: `https://runnercloud.example.com/${deployId}` });
});

// helper function for audit logging
function auditLog(eventType, runnerId, actor, details, result) {
  const entry = {
    timestamp: new Date().toISOString(),
    event_type: eventType,
    runner_id: runnerId,
    actor: actor || 'system',
    details: details || {},
    result: result || 'success',
    audit_id: `audit-${crypto.randomBytes(8).toString('hex')}`
  };
  auditLogs.push(entry);
  if (auditLogs.length > 10000) auditLogs.shift(); // keep last 10k entries
  return entry;
}

// ===== API v1: Token Management =====

// POST /api/v1/auth/token - Request new ephemeral token
app.post('/api/v1/auth/token', (req, res) => {
  const { ttl_seconds = 3600, job_type = 'ci-build', resource_tags = {} } = req.body;
  
  if (ttl_seconds < 60 || ttl_seconds > 28800) {
    return res.status(400).json({ error: 'invalid_request', error_description: 'ttl_seconds must be between 60 and 28800' });
  }
  
  const accessToken = `ep_${crypto.randomBytes(16).toString('hex')}`;
  const issuedAt = new Date();
  const expiresAt = new Date(issuedAt.getTime() + ttl_seconds * 1000);
  
  res.status(201).json({
    access_token: accessToken,
    token_type: 'Bearer',
    expires_in: ttl_seconds,
    ttl_seconds: ttl_seconds,
    issued_at: issuedAt.toISOString(),
    expires_at: expiresAt.toISOString(),
    job_type: job_type
  });
});

// POST /api/v1/auth/refresh - Refresh token
app.post('/api/v1/auth/refresh', (req, res) => {
  const { refresh_token, ttl_seconds = 3600 } = req.body;
  
  if (!refresh_token) {
    return res.status(401).json({ error: 'invalid_token', error_description: 'refresh_token required' });
  }
  
  const newAccessToken = `ep_${crypto.randomBytes(16).toString('hex')}`;
  const newRefreshToken = `rt_${crypto.randomBytes(16).toString('hex')}`;
  const issuedAt = new Date();
  const expiresAt = new Date(issuedAt.getTime() + ttl_seconds * 1000);
  
  res.status(201).json({
    access_token: newAccessToken,
    refresh_token: newRefreshToken,
    expires_in: ttl_seconds,
    issued_at: issuedAt.toISOString(),
    expires_at: expiresAt.toISOString()
  });
});

// POST /api/v1/auth/revoke - Revoke token
app.post('/api/v1/auth/revoke', (req, res) => {
  const { token, reason = 'manual_revoke' } = req.body;
  
  if (!token) {
    return res.status(400).json({ error: 'invalid_request', error_description: 'token required' });
  }
  
  // In production, would store revoked tokens in a blacklist
  res.status(204).end();
});

// ===== API v1: Runner Registration & Management =====

// POST /api/v1/runners/register - Register new runner
app.post('/api/v1/runners/register', (req, res) => {
  const token = req.headers.authorization?.replace('Bearer ', '');
  if (!token) return res.status(401).json({ error: 'invalid_token' });
  
  const { name, os, arch = 'x86_64', labels = [], pool = 'default', vpc_id, region, max_jobs = 4, network_config = {} } = req.body;
  
  if (!name || !os) {
    return res.status(400).json({ error: 'invalid_request', error_description: 'name and os required' });
  }
  
  const runnerId = `r-${crypto.randomBytes(8).toString('hex')}`;
  const registrationToken = `reg_${crypto.randomBytes(16).toString('hex')}`;
  
  const runner = {
    runner_id: runnerId,
    name: name,
    os: os,
    arch: arch,
    labels: labels,
    pool: pool,
    vpc_id: vpc_id,
    region: region,
    max_jobs: max_jobs,
    status: 'provisioning',
    created_at: new Date().toISOString(),
    registration_expires_at: new Date(Date.now() + 600000).toISOString(), // 10 min
    last_heartbeat: null,
    current_job: null,
    metrics: { cpu_percent: 0, memory_percent: 0, disk_percent: 0 }
  };
  
  runners.push(runner);
  auditLog('runner_registered', runnerId, token.substring(0, 20) + '...', { os, pool, vpc_id }, 'success');
  
  // Mark as running after a short delay
  setTimeout(() => {
    const r = runners.find(x => x.runner_id === runnerId);
    if (r) r.status = 'running';
  }, 1000);
  
  res.status(201).json({
    runner_id: runnerId,
    registration_token: registrationToken,
    status: runner.status,
    created_at: runner.created_at,
    registration_expires_at: runner.registration_expires_at,
    heartbeat: {
      required: true,
      interval_seconds: parseInt(process.env.HEARTBEAT_INTERVAL || '30'),
      timeout_seconds: parseInt(process.env.HEARTBEAT_TIMEOUT || '60')
    },
    config: {
      auth_method: 'bearer',
      control_plane_url: `${process.env.CONTROL_PLANE_URL || 'https://managed-auth.example.com'}`,
      certificate_chain: 'TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384'
    }
  });
});

// GET /api/v1/runners/:runner_id - Get runner status
app.get('/api/v1/runners/:runner_id', (req, res) => {
  const { runner_id } = req.params;
  const runner = runners.find(r => r.runner_id === runner_id);
  
  if (!runner) {
    return res.status(404).json({ error: 'resource_not_found', error_description: 'Runner not found' });
  }
  
  res.json({
    runner_id: runner.runner_id,
    name: runner.name,
    status: runner.status,
    created_at: runner.created_at,
    last_heartbeat: runner.last_heartbeat,
    current_job: runner.current_job,
    metrics: runner.metrics,
    next_ephemeral_token_at: new Date(Date.now() + 3600000).toISOString() // 1 hour
  });
});

// DELETE /api/v1/runners/:runner_id - Deregister runner (graceful shutdown)
app.delete('/api/v1/runners/:runner_id', (req, res) => {
  const { runner_id } = req.params;
  const { reason = 'scheduled_maintenance', drain_timeout = 300 } = req.body;
  
  const runner = runners.find(r => r.runner_id === runner_id);
  if (!runner) {
    return res.status(404).json({ error: 'resource_not_found' });
  }
  
  runner.status = 'draining';
  const drainStartedAt = new Date();
  const drainDeadline = new Date(drainStartedAt.getTime() + drain_timeout * 1000);
  
  auditLog('runner_deregistered', runner_id, 'system', { reason, drain_timeout }, 'success');
  
  // Auto-terminate after drain timeout
  setTimeout(() => {
    const idx = runners.findIndex(r => r.runner_id === runner_id);
    if (idx >= 0) {
      runners[idx].status = 'terminated';
    }
  }, drain_timeout * 1000);
  
  res.status(202).json({
    runner_id: runner_id,
    status: 'draining',
    drain_timeout: drain_timeout,
    drain_started_at: drainStartedAt.toISOString(),
    drain_deadline: drainDeadline.toISOString()
  });
});

// ===== API v1: Heartbeat & Health Monitoring =====

// POST /api/v1/runners/:runner_id/heartbeat - Send periodic heartbeat
app.post('/api/v1/runners/:runner_id/heartbeat', (req, res) => {
  const token = req.headers.authorization?.replace('Bearer ', '');
  if (!token) return res.status(401).json({ error: 'invalid_token' });
  
  const { runner_id } = req.params;
  const { timestamp, status = 'idle', current_job_id, job_history = [], metrics = {}, system_info = {} } = req.body;
  
  const runner = runners.find(r => r.runner_id === runner_id);
  if (!runner) {
    return res.status(404).json({ error: 'resource_not_found' });
  }
  
  // Update runner state
  runner.last_heartbeat = timestamp || new Date().toISOString();
  runner.status = status;
  runner.current_job = current_job_id ? { id: current_job_id } : null;
  runner.metrics = { ...metrics };
  
  heartbeats[runner_id] = runner.last_heartbeat;
  auditLog('heartbeat_received', runner_id, 'runner', { status, metrics }, 'success');
  
  const nextHeartbeatAt = new Date(Date.now() + (parseInt(process.env.HEARTBEAT_INTERVAL || '30') * 1000));
  const nextTokenRotationAt = new Date(Date.now() + 3000000); // ~50 min
  
  res.json({
    runner_id: runner_id,
    heartbeat_received: true,
    next_heartbeat_at: nextHeartbeatAt.toISOString(),
    next_token_rotation_at: nextTokenRotationAt.toISOString(),
    commands: [] // Server can send commands here
  });
});

// POST /api/v1/runners/:runner_id/healthcheck - Detailed health check
app.post('/api/v1/runners/:runner_id/healthcheck', (req, res) => {
  const token = req.headers.authorization?.replace('Bearer ', '');
  if (!token) return res.status(401).json({ error: 'invalid_token' });
  
  const { runner_id } = req.params;
  const { timestamp, health = {} } = req.body;
  
  const runner = runners.find(r => r.runner_id === runner_id);
  if (!runner) {
    return res.status(404).json({ error: 'resource_not_found' });
  }
  
  let healthStatus = 'healthy';
  const recommendations = [];
  
  if (health.disk_available_gb < 10) {
    healthStatus = 'degraded';
    recommendations.push('Low disk space available');
  }
  if (!health.vault_connectivity) {
    healthStatus = 'critical';
    recommendations.push('Cannot connect to Vault');
  }
  
  auditLog('healthcheck_received', runner_id, 'runner', health, 'success');
  
  res.json({
    health_status: healthStatus,
    last_check: timestamp || new Date().toISOString(),
    recommendations: recommendations
  });
});

// GET /api/v1/audit/logs - Retrieve audit logs
app.get('/api/v1/audit/logs', (req, res) => {
  const { runner_id, event_type, start_time, end_time, limit = 100 } = req.query;
  
  let filtered = auditLogs;
  
  if (runner_id) {
    filtered = filtered.filter(log => log.runner_id === runner_id);
  }
  
  if (event_type) {
    filtered = filtered.filter(log => log.event_type === event_type);
  }
  
  if (start_time || end_time) {
    const start = start_time ? new Date(start_time) : new Date(0);
    const end = end_time ? new Date(end_time) : new Date();
    filtered = filtered.filter(log => {
      const time = new Date(log.timestamp);
      return time >= start && time <= end;
    });
  }
  
  const total = filtered.length;
  const paginated = filtered.slice(-parseInt(limit));
  
  res.json({
    logs: paginated,
    total: total,
    has_more: total > parseInt(limit)
  });
});

// record usage (called by runner agents periodically)
app.post('/usage', (req, res) => {
  const { runnerId, seconds } = req.body;
  if (!runnerId || !seconds) return res.status(400).json({ error: 'runnerId and seconds required' });
  billingRecords.push({ runnerId, seconds, timestamp: new Date().toISOString() });
  res.status(204).end();
});

// healthcheck
app.get('/health', (req, res) => res.json({
  status: 'ok',
  timestamp: new Date().toISOString(),
  version: '1.0.0',
  runners: { total: runners.length, active: runners.filter(r => r.status === 'running').length }
}));

app.listen(port, '0.0.0.0', () => {
  logger.info('managed-auth service listening', { port });
});
