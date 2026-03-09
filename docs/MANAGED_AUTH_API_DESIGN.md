# Managed-Homing Control Plane: Runner Registration API Design

## Overview

This document specifies the centralized Runner Registration API (Managed-Homing Control Plane) that enables:

- **Cross-VPC Runner Registration**: Secure registration of runners across air-gapped and isolated VPCs
- **Ephemeral Token Lifecycle**: Short-lived tokens with dynamic TTL based on job complexity
- **Heartbeat Monitoring**: Periodic health checks to track runner availability
- **Air-Gapped Support**: mTLS and certificate-based auth for isolated environments
- **Multi-Tenant Isolation**: Organization-level isolation with audit logging

## Architecture

```
┌─────────────────────────────────────┐
│  Managed-Homing Control Plane API   │
│  (Centralized Authorization)        │
└─────────────────────────────────────┘
            ↓
  ┌─────────────┬─────────────┬──────────┐
  │             │             │          │
┌─┴──────┐  ┌──┴──────┐  ┌───┴───────┐ ┌─┴───────┐
│ VPC-1  │  │ VPC-2   │  │ VPC-3     │ │Airgap-1 │
│Runners │  │ Runners │  │ Runners   │ │Runners  │
└────────┘  └─────────┘  └───────────┘ └─────────┘
```

## API Specification (OpenAPI 3.0)

### Base URL
```
https://managed-auth.example.com/api/v1
```

### Authentication Methods

#### 1. OAuth2 (GitHub App)
- Initial onboarding and authorization
- Long-lived refresh token (7 days)
- Short-lived access tokens (1 hour)

#### 2. mTLS (Air-Gapped Environments)
- Client certificate authentication
- Mutual certificate validation
- Certificate pinning support

#### 3. OIDC Token (Ephemeral)
- Kubernetes service account tokens (K8s deployments)
- Time-limited tokens (15 minutes to 8 hours)
- Auto-renewal capability

### Endpoints

#### 1. Authentication & Token Management

##### `POST /auth/token`
**Request new ephemeral token**

```yaml
Request:
  Method: POST
  Headers:
    Content-Type: application/json
    Authorization: Bearer {refresh_token}
  Body:
    {
      "ttl_seconds": 3600,
      "job_type": "ci-build",  # or "integration-test", "deploy"
      "resource_tags": {
        "team": "platform",
        "queue": "ci-linux"
      }
    }

Response (201):
  {
    "access_token": "ep_xyz123...",
    "token_type": "Bearer",
    "expires_in": 3600,
    "ttl_seconds": 3600,
    "issued_at": "2026-03-09T12:00:00Z",
    "expires_at": "2026-03-09T13:00:00Z",
    "job_type": "ci-build"
  }

Errors:
  401 Unauthorized - Invalid refresh token
  400 Bad Request - Invalid TTL (min: 60s, max: 28800s)
```

**TTL Calculation Logic:**
```
if job_type == "quick-test":
  ttl = min(ttl_requested, 900)      # 15 minutes max
elif job_type == "build":
  ttl = min(ttl_requested, 3600)     # 1 hour max
elif job_type == "integration-test":
  ttl = min(ttl_requested, 7200)     # 2 hours max
elif job_type == "deploy":
  ttl = min(ttl_requested, 28800)    # 8 hours max
else:
  ttl = min(ttl_requested, 1800)     # 30 minutes default
```

##### `POST /auth/refresh`
**Refresh expired token**

```yaml
Request:
  Method: POST
  Headers:
    Content-Type: application/json
  Body:
    {
      "refresh_token": "rt_abc456...",
      "ttl_seconds": 3600
    }

Response (201):
  {
    "access_token": "ep_newtoken...",
    "refresh_token": "rt_newrefresh...",
    "expires_in": 3600,
    "issued_at": "2026-03-09T13:00:00Z"
  }

Errors:
  401 Unauthorized - Invalid or expired refresh token
  403 Forbidden - Token lifecycle limit exceeded
```

##### `POST /auth/revoke`
**Revoke token**

```yaml
Request:
  Method: POST
  Headers:
    Authorization: Bearer {access_token}
  Body:
    {
      "token": "ep_xyz123...",
      "reason": "runner_shutdown"
    }

Response (204):
  # No content

Errors:
  401 Unauthorized - Invalid token
```

#### 2. Runner Registration

##### `POST /runners/register`
**Register a new runner**

```yaml
Request:
  Method: POST
  Headers:
    Content-Type: application/json
    Authorization: Bearer {access_token}
    X-Runner-Id: {uuid}  # Optional, system generates if missing
  Body:
    {
      "name": "runner-linux-01",
      "os": "ubuntu-latest",
      "arch": "x86_64",
      "labels": ["docker", "linux", "self-hosted"],
      "pool": "default",
      "vpc_id": "vpc-0x1234",
      "region": "us-east-1",
      "max_jobs": 4,
      "network_config": {
        "allow_public_ip": false,
        "secure_tunnel": true,
        "mtls_required": true
      }
    }

Response (201):
  {
    "runner_id": "r-7f8g9h0i",
    "registration_token": "reg_xyz789...",
    "status": "provisioning",
    "created_at": "2026-03-09T12:00:00Z",
    "registration_expires_at": "2026-03-09T12:10:00Z",
    "heartbeat": {
      "required": true,
      "interval_seconds": 30,
      "timeout_seconds": 60
    },
    "config": {
      "auth_method": "oidc",
      "control_plane_url": "https://managed-auth.example.com",
      "certificate_chain": "-----BEGIN CERTIFICATE-----\n..."
    }
  }

Errors:
  401 Unauthorized - Invalid access token
  409 Conflict - Runner already registered
  400 Bad Request - Invalid registration data
```

##### `GET /runners/{runner_id}`
**Get runner status**

```yaml
Request:
  Method: GET
  Headers:
    Authorization: Bearer {access_token}

Response (200):
  {
    "runner_id": "r-7f8g9h0i",
    "name": "runner-linux-01",
    "status": "running",  # provisioning | running | idle | offline | terminated
    "created_at": "2026-03-09T12:00:00Z",
    "last_heartbeat": "2026-03-09T12:05:30Z",
    "current_job": {
      "id": "job-123",
      "status": "running",
      "started_at": "2026-03-09T12:03:00Z"
    },
    "metrics": {
      "cpu_percent": 45,
      "memory_percent": 62,
      "disk_percent": 28
    },
    "next_ephemeral_token_at": "2026-03-09T12:50:00Z"
  }

Errors:
  401 Unauthorized - Invalid token
  404 Not Found - Runner not found
  403 Forbidden - Access denied
```

##### `DELETE /runners/{runner_id}`
**Deregister runner (graceful shutdown)**

```yaml
Request:
  Method: DELETE
  Headers:
    Authorization: Bearer {access_token}
  Body:
    {
      "reason": "scheduled_maintenance",  # scheduled_maintenance | resource_optimization | error_recovery
      "drain_timeout": 300
    }

Response (202):
  {
    "runner_id": "r-7f8g9h0i",
    "status": "draining",
    "drain_timeout": 300,
    "drain_started_at": "2026-03-09T12:10:00Z",
    "drain_deadline": "2026-03-09T12:15:00Z"
  }

Errors:
  401 Unauthorized
  404 Not Found
  409 Conflict - Runner already shutting down
```

#### 3. Heartbeat & Health

##### `POST /runners/{runner_id}/heartbeat`
**Send periodic heartbeat**

```yaml
Request:
  Method: POST
  Headers:
    Content-Type: application/json
    Authorization: Bearer {access_token}
  Body:
    {
      "timestamp": "2026-03-09T12:05:30Z",
      "status": "idle",  # idle | running | draining
      "current_job_id": null,
      "job_history": [
        {
          "id": "job-120",
          "status": "completed",
          "duration": 45,
          "result": "success"
        }
      ],
      "metrics": {
        "cpu_percent": 15,
        "memory_percent": 32,
        "disk_percent": 18,
        "network_io": 1024
      },
      "system_info": {
        "load_average": [0.5, 0.6, 0.4],
        "uptime": 86400,
        "process_count": 45
      }
    }

Response (200):
  {
    "runner_id": "r-7f8g9h0i",
    "heartbeat_received": true,
    "next_heartbeat_at": "2026-03-09T12:06:00Z",
    "next_token_rotation_at": "2026-03-09T12:50:00Z",
    "commands": []  # Server can send commands to runner
  }

Errors:
  401 Unauthorized - Invalid token
  404 Not Found - Runner not found
  503 Service Unavailable - Control plane temporarily unavailable
```

**Heartbeat Monitoring Rules:**
- Interval: 30 seconds (default, configurable)
- Timeout: 2 missed heartbeats (60 seconds) → Runner marked offline
- 3 missed heartbeats (90 seconds) → Runner terminated, new instance provisioned
- Exponential backoff on failure (30s → 60s → 120s)

##### `POST /runners/{runner_id}/healthcheck`
**Detailed health check (less frequent)**

```yaml
Request:
  Method: POST
  Headers:
    Authorization: Bearer {access_token}
  Body:
    {
      "timestamp": "2026-03-09T12:05:30Z",
      "health": {
        "docker_socket": true,
        "disk_available_gb": 150,
        "network_connectivity": true,
        "vault_connectivity": true
      }
    }

Response (200):
  {
    "health_status": "healthy",  # healthy | degraded | critical
    "last_check": "2026-03-09T12:05:30Z",
    "recommendations": []
  }
```

#### 4. Air-Gapped VPC Support

##### `POST /bridge/register`
**Register an air-gapped VPC bridge**

```yaml
Request:
  Method: POST
  Headers:
    Content-Type: application/json
    Authorization: Bearer {access_token}
  Body:
    {
      "vpc_id": "vpc-airgap-001",
      "bridge_name": "bridge-vpc-worker-1",
      "certificate": "-----BEGIN CERTIFICATE-----\n...",
      "certificate_chain": "-----BEGIN CERTIFICATE-----\n...",
      "bridge_public_key": "-----BEGIN PUBLIC KEY-----\n...",
      "allowed_cidrs": ["10.0.0.0/8"],
      "mtls_required": true
    }

Response (201):
  {
    "bridge_id": "br-xyz123",
    "vpc_id": "vpc-airgap-001",
    "status": "registered",
    "certificate_expires_at": "2026-06-09T12:00:00Z",
    "connection_endpoint": "bridge.managed-auth.example.com:9443",
    "tunnel_config": {
      "protocol": "mtls",
      "cipher_suites": ["TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384"],
      "tls_version_min": "1.3"
    }
  }

Errors:
  401 Unauthorized
  400 Bad Request - Invalid certificate
```

##### `GET /bridge/{bridge_id}/tunnels`
**List active tunnels for bridge**

```yaml
Response (200):
  {
    "bridge_id": "br-xyz123",
    "tunnels": [
      {
        "tunnel_id": "t-1",
        "runner_id": "r-001",
        "status": "connected",
        "connected_since": "2026-03-09T10:00:00Z",
        "last_activity": "2026-03-09T12:05:30Z"
      }
    ]
  }
```

#### 5. Audit & Logging

##### `GET /audit/logs`
**Retrieve audit logs**

```yaml
Request:
  Method: GET
  Query Parameters:
    runner_id: {runner_id}
    event_type: register|heartbeat|token_issue|token_revoke|error
    start_time: 2026-03-01T00:00:00Z
    end_time: 2026-03-09T23:59:59Z
    limit: 1000

Response (200):
  {
    "logs": [
      {
        "timestamp": "2026-03-09T12:00:05Z",
        "event_type": "runner_registered",
        "runner_id": "r-7f8g9h0i",
        "actor": "user@example.com",
        "details": {
          "os": "ubuntu-latest",
          "pool": "default",
          "vpc_id": "vpc-0x1234"
        },
        "result": "success",
        "audit_id": "audit-xyz789"
      }
    ],
    "total": 42,
    "has_more": true
  }

Errors:
  401 Unauthorized
  403 Forbidden - Access denied to audit logs
```

### Error Response Format

All errors follow this format:

```json
{
  "error": "error_code",
  "error_description": "Human-readable description",
  "correlation_id": "req-abc123",
  "timestamp": "2026-03-09T12:00:00Z",
  "details": {
    "field": "error_field",
    "reason": "specific reason"
  }
}
```

**Standard Error Codes:**
- `invalid_token`: Token invalid or expired
- `insufficient_permission`: Access denied
- `resource_not_found`: Resource doesn't exist
- `resource_conflict`: Resource already exists or conflict
- `invalid_request`: Malformed request
- `server_error`: Internal server error

## Token Lifecycle

### Flow Diagram

```
┌─────────────────────────────────────────────────┐
│ 1. Runner authenticates via OAuth/mTLS/OIDC     │
└──────────────────────┬──────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────┐
│ 2. Receive refresh token (7-day TTL)            │
└──────────────────────┬──────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────┐
│ 3. Request access token (1-8 hour TTL)          │
│    TTL based on job_type                        │
└──────────────────────┬──────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────┐
│ 4. Runner uses access token for requests        │
└──────────────────────┬──────────────────────────┘
                       │
        ┌──────────────┼──────────────┐
        │              │              │
   Job takes   Job complete    Token expires
   < 5 minutes        │         │
        │              ▼         ▼
        │         ┌─────────────────────┐
        │         │ Automatic renewal   │
        │         │ (within 10min)      │
        │         └─────────────────────┘
        │              │
        ▼              ▼
    ┌─────────────────────────────────────┐
    │ 5. Token reaches max lifetime:      │
    │    Revoke + reissue new refresh     │
    └─────────────────────────────────────┘

Max token validity: 7 days (hard limit)
```

## Security Considerations

### 1. Token Storage
- Tokens stored in secure credential store (HashiCorp Vault)
- Never logged or exposed in error messages
- Encryption-at-rest using AES-256-GCM

### 2. Transport Security
- All API communication over HTTPS/TLS 1.3+
- mTLS required for air-gapped environments
- Certificate pinning for critical connections

### 3. Rate Limiting
- Per-runner rate limits: 100 req/min
- Per-token rate limits: 50 req/min
- Per-IP rate limits: 1000 req/min
- Exponential backoff for failures

### 4. Audit Logging
- All registration/authentication events logged
- Immutable audit trail (append-only)
- Audit logs encrypted at-rest
- 90-day retention (configurable)

### 5. Air-Gapped Environment Isolation
- mTLS certificate validation
- Network ACLs enforced
- Inter-VPC communication only through bridge
- No direct internet connectivity required

## Deployment

### Docker
```bash
docker run -d \
  -e PORT=8080 \
  -e VAULT_ADDR=https://vault.example.com \
  -e VAULT_TOKEN=... \
  -e DATABASE_URL=postgres://... \
  -p 8080:8080 \
  runnercloud/managed-auth:latest
```

### Kubernetes
See `docs/k8s-deployment.yaml`

### Terraform
See `terraform/modules/managed-auth`

## Testing

### Integration Tests
```bash
cd services/managed-auth/tests
bash integration_test.sh
```

### Load Testing
```bash
k6 run tests/load-test.js
```

## References

- OpenAPI 3.0 Spec: [managed-auth-openapi.yaml](./managed-auth-openapi.yaml)
- Terraform Module: [terraform/modules/managed-auth](../../terraform/modules/managed-auth/README.md)
- Deployment Guide: [docs/MANAGED_AUTH_DEPLOYMENT.md](../MANAGED_AUTH_DEPLOYMENT.md)
