# Managed-Auth Testing Guide

## Overview

This document provides instructions for testing the Managed-Auth Runner Registration API, including integration tests and manual verification.

## Prerequisites

- Node.js 18+
- curl or Postman
- Running managed-auth service (`npm start`)

## Integration Tests

### Running All Tests

```bash
cd services/managed-auth
npm test
```

Or directly:

```bash
bash tests/registration_and_heartbeat_test.sh
```

### Custom Base URL

```bash
BASE_URL=http://managed-auth.example.com:8080 \
bash tests/registration_and_heartbeat_test.sh
```

## Manual Testing

### 1. Health Check

```bash
curl http://localhost:8080/health
```

**Expected Response:**
```json
{
  "status": "ok",
  "timestamp": "2026-03-09T12:00:00Z",
  "version": "1.0.0",
  "runners": {
    "total": 0,
    "active": 0
  }
}
```

### 2. Create Access Token

```bash
curl -X POST http://localhost:8080/api/v1/auth/token \
  -H "Content-Type: application/json" \
  -d '{
    "ttl_seconds": 3600,
    "job_type": "ci-build"
  }'
```

**Expected Response:**
```json
{
  "access_token": "ep_...",
  "token_type": "Bearer",
  "expires_in": 3600,
  "ttl_seconds": 3600,
  "issued_at": "2026-03-09T12:00:00Z",
  "expires_at": "2026-03-09T13:00:00Z",
  "job_type": "ci-build"
}
```

**Save the `access_token` for subsequent requests.**

### 3. Register Runner

```bash
export ACCESS_TOKEN="ep_..."

curl -X POST http://localhost:8080/api/v1/runners/register \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d '{
    "name": "runner-linux-01",
    "os": "ubuntu-latest",
    "arch": "x86_64",
    "labels": ["docker", "linux"],
    "pool": "default",
    "vpc_id": "vpc-12345",
    "region": "us-east-1"
  }'
```

**Expected Response:**
```json
{
  "runner_id": "r-abc123...",
  "registration_token": "reg_...",
  "status": "provisioning",
  "created_at": "2026-03-09T12:00:00Z",
  "registration_expires_at": "2026-03-09T12:10:00Z",
  "heartbeat": {
    "required": true,
    "interval_seconds": 30,
    "timeout_seconds": 60
  },
  "config": {
    "auth_method": "bearer",
    "control_plane_url": "https://managed-auth.example.com"
  }
}
```

**Save the `runner_id` and `registration_token`.**

### 4. Get Runner Status

```bash
export RUNNER_ID="r-..."

curl http://localhost:8080/api/v1/runners/$RUNNER_ID \
  -H "Authorization: Bearer $ACCESS_TOKEN"
```

**Expected Response:**
```json
{
  "runner_id": "r-...",
  "name": "runner-linux-01",
  "status": "running",
  "created_at": "2026-03-09T12:00:00Z",
  "last_heartbeat": null,
  "current_job": null,
  "metrics": {
    "cpu_percent": 0,
    "memory_percent": 0,
    "disk_percent": 0
  }
}
```

### 5. Send Heartbeat

```bash
curl -X POST http://localhost:8080/api/v1/runners/$RUNNER_ID/heartbeat \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d '{
    "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
    "status": "idle",
    "current_job_id": null,
    "metrics": {
      "cpu_percent": 15.5,
      "memory_percent": 32.2,
      "disk_percent": 18.9
    },
    "system_info": {
      "load_average": [0.5, 0.6, 0.4],
      "uptime": 86400
    }
  }'
```

**Expected Response:**
```json
{
  "runner_id": "r-...",
  "heartbeat_received": true,
  "next_heartbeat_at": "2026-03-09T12:00:30Z",
  "next_token_rotation_at": "2026-03-09T12:50:00Z",
  "commands": []
}
```

### 6. Send Healthcheck

```bash
curl -X POST http://localhost:8080/api/v1/runners/$RUNNER_ID/healthcheck \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d '{
    "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
    "health": {
      "docker_socket": true,
      "disk_available_gb": 150,
      "network_connectivity": true,
      "vault_connectivity": true
    }
  }'
```

**Expected Response:**
```json
{
  "health_status": "healthy",
  "last_check": "2026-03-09T12:00:00Z",
  "recommendations": []
}
```

### 7. Get Audit Logs

```bash
curl "http://localhost:8080/api/v1/audit/logs?runner_id=$RUNNER_ID" \
  -H "Authorization: Bearer $ACCESS_TOKEN"
```

**Expected Response:**
```json
{
  "logs": [
    {
      "timestamp": "2026-03-09T12:00:05Z",
      "event_type": "runner_registered",
      "runner_id": "r-...",
      "actor": "ep_...",
      "details": {
        "os": "ubuntu-latest",
        "pool": "default"
      },
      "result": "success",
      "audit_id": "audit-xyz"
    }
  ],
  "total": 1,
  "has_more": false
}
```

### 8. Deregister Runner (Graceful Shutdown)

```bash
curl -X DELETE http://localhost:8080/api/v1/runners/$RUNNER_ID \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d '{
    "reason": "scheduled_maintenance",
    "drain_timeout": 60
  }'
```

**Expected Response:**
```json
{
  "runner_id": "r-...",
  "status": "draining",
  "drain_timeout": 60,
  "drain_started_at": "2026-03-09T12:05:00Z",
  "drain_deadline": "2026-03-09T12:06:00Z"
}
```

## Load Testing

Using k6 for load testing:

```bash
k6 run tests/load-test.js \
  --vus 10 \
  --duration 30s \
  --stage 10s:100 \
  --stage 20s:100 \
  --stage 10s:0
```

## Troubleshooting

### Tests failing with "connection refused"

1. Ensure service is running: `npm start`
2. Check port: `lsof -i :8080`
3. Verify BASE_URL is correct

### Heartbeat timeouts

1. Check heartbeat interval: `echo $HEARTBEAT_INTERVAL`
2. Verify token expiration: Check `expires_at` field
3. Review logs: `tail -f /tmp/managed-auth.log`

### Runner not transitioning to "running"

1. Check service logs for errors
2. Verify registration token is valid
3. Confirm runner received config

## Performance Benchmarks

Expected API response times (p95):

| Endpoint | Latency |
|----------|---------|
| POST /auth/token | < 50ms |
| POST /runners/register | < 100ms |
| GET /runners/{id} | < 30ms |
| POST /runners/{id}/heartbeat | < 50ms |

## Continuous Integration

Tests are automatically run on:
- Push to main branch
- Pull requests
- Daily at 2 AM UTC

See `.github/workflows/test-managed-auth.yml`

## References

- [API Design](MANAGED_AUTH_API_DESIGN.md)
- [OpenAPI Specification](./managed-auth-openapi.yaml)
- [Deployment Guide](./MANAGED_AUTH_DEPLOYMENT.md)
