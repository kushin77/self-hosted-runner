# Managed-Auth Service Module

Terraform module for deploying the centralized runner registration API (Managed-Homing Control Plane).

## Features

- **Kubernetes Deployment**: Container-based service with auto-scaling
- **mTLS Support**: Certificate management for air-gapped environments  
- **Database Integration**: PostgreSQL backend for runner registry
- **Vault Integration**: Secret management and token lifecycle
- **Load Balancer**: ALB/NLB for HA and failover
- **Monitoring**: Built-in metrics export and Prometheus scraping

## Usage

```hcl
module "managed_auth" {
  source = "../../modules/managed-auth"

  cluster_name        = "runner-cluster"
  namespace           = "managed-auth"
  replica_count       = 3
  
  vault_addr          = var.vault_address
  vault_auth_method   = "kubernetes"
  
  database_url        = aws_db_instance.postgres.endpoint
  database_name       = "managed_auth"
  
  certificate_arn     = aws_acm_certificate.managed_auth.arn
  
  enable_mtls         = true
  mtls_ca_secret      = aws_secretsmanager_secret.mtls_ca.name
}
```

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `cluster_name` | string | - | Kubernetes cluster name |
| `namespace` | string | `"managed-auth"` | Kubernetes namespace |
| `replica_count` | number | `3` | Number of pod replicas |
| `image_repository` | string | `"gcr.io/runnercloud/managed-auth"` | Docker image repository |
| `image_tag` | string | `"latest"` | Docker image tag |
| `port` | number | `8080` | Service port |
| `vault_addr` | string | - | HashiCorp Vault address |
| `vault_auth_method` | string | `"kubernetes"` | Vault auth method |
| `database_url` | string | - | PostgreSQL connection string |
| `database_name` | string | `"managed_auth"` | Database name |
| `certificate_arn` | string | - | AWS ACM certificate ARN |
| `enable_mtls` | bool | `true` | Enable mTLS for clients |
| `mtls_ca_secret` | string | - | AWS Secrets Manager secret for mTLS CA |
| `token_ttl_max` | number | `28800` | Maximum token TTL (seconds) |
| `heartbeat_interval` | number | `30` | Heartbeat interval (seconds) |
| `heartbeat_timeout` | number | `60` | Heartbeat timeout (seconds) |
| `enable_monitoring` | bool | `true` | Enable Prometheus monitoring |
| `enable_tracing` | bool | `true` | Enable OpenTelemetry tracing |

## Outputs

| Name | Type | Description |
|------|------|-------------|
| `service_url` | string | Public service URL |
| `service_endpoint` | string | Internal Kubernetes service endpoint |
| `service_port` | number | Service port |
| `deployment_name` | string | Kubernetes deployment name |
| `namespace` | string | Kubernetes namespace |
| `metrics_port` | number | Prometheus metrics port |

## Architecture

```
┌─────────────────────────────────────┐
│      AWS Application Load Balancer  │ (HTTPS, certificate pinning)
└──────────────────┬──────────────────┘
                   │
        ┌──────────┴──────────┐
        │                     │
    ┌───▼───┐            ┌───▼───┐
    │ Pod 1 │            │ Pod 2 │   (3+ Replicas)
    └───┬───┘            └───┬───┘
        │                    │
        └──────────┬─────────┘
                   │
            ┌──────▼──────┐
            │  PostgreSQL │ (Runner registry)
            └─────────────┘
            
            ┌──────────────┐
            │ HashiCorp    │ (Token management)
            │ Vault        │
            └──────────────┘
```

## Security

- **Network Policies**: Restrict traffic to necessary pods only
- **RBAC**: Service accounts with minimal permissions
- **Secret Management**: All secrets via Vault or AWS Secrets Manager
- **TLS**: Enforced for all connections
- **mTLS**: Optional client certificate authentication
- **Audit Logging**: All API requests logged to immutable audit trail

## Deployment Options

### Option 1: Kubernetes (Recommended)

```bash
terraform apply -var="cluster_name=prod-runners"
```

### Option 2: Docker Compose (Development)

See `docker-compose.dev.yml`

### Option 3: AWS ECS

```hcl
deployment_type = "ecs"
ecs_cluster_name = "runner-cluster"
```

## Monitoring

### Prometheus Metrics

Available at `http://localhost:9091/metrics`:

- `managed_auth_requests_total`: Total API requests
- `managed_auth_request_duration_seconds`: Request latency
- `managed_auth_active_runners`: Number of active runners
- `managed_auth_token_issued_total`: Tokens issued
- `managed_auth_heartbeat_received_total`: Heartbeats received
- `managed_auth_heartbeat_missed_total`: Missed heartbeats

### Dashboards

- Grafana dashboard: See `dashboards/managed-auth.json`
- CloudWatch dashboard: Auto-created in AWS

## Troubleshooting

### Runners not connecting

1. Check service is running: `kubectl describe service managed-auth`
2. Review logs: `kubectl logs -f deployment/managed-auth`
3. Test API: `curl -H "Authorization: Bearer $TOKEN" https://managed-auth/api/v1/health`

### Token expiration issues

1. Verify Vault connectivity: `kubectl exec -it managed-auth-0 -- curl http://vault:8200/v1/sys/health`
2. Check token TTL settings: `kubectl get deployment managed-auth -o yaml`

### Database connectivity

1. Verify connection string: `echo $DATABASE_URL`
2. Test connection: `psql $DATABASE_URL -c "SELECT 1"`

## References

- [API Design](../MANAGED_AUTH_API_DESIGN.md)
- [OpenAPI Spec](../managed-auth-openapi.yaml)
- [Deployment Guide](../MANAGED_AUTH_DEPLOYMENT.md)
- [Troubleshooting](../MANAGED_AUTH_TROUBLESHOOTING.md)
