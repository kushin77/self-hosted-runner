# Phase 2: Infrastructure-as-Code Terraform Implementation

**Status**: In Progress  
**Start Date**: March 11, 2026  
**Target Completion**: March 18, 2026  
**Constraint Profile**: Immutable, Ephemeral, Idempotent, No-Ops, Hands-Off  

## 📋 Objective

Build production-grade Terraform modules for complete GCP infrastructure deployment:
- Cloud Run (backend + frontend containers)
- Cloud SQL (PostgreSQL with backups)
- Redis Memorystore (session/cache layer)
- VPC & networking (private endpoints, firewalls)
- IAM & service accounts (OIDC, minimal permissions)

## 🎯 Deliverables

### Terraform Module Structure
```
infra/terraform/
├── modules/
│   ├── cloud_run/          # Container deployment
│   ├── cloud_sql/          # PostgreSQL database
│   ├── redis/              # Cache layer
│   ├── vpc_networking/     # Network isolation
│   ├── iam/                # Service accounts & roles
│   └── storage/            # Cloud Storage buckets
├── environments/
│   ├── dev.tfvars          # Development
│   ├── staging.tfvars      # Staging
│   └── prod.tfvars         # Production
├── main.tf                 # Primary configuration
├── variables.tf            # Input variables
├── outputs.tf              # Output definitions
├── terraform.tfvars        # Default values
└── backend.tf              # GCS remote state (immutable)
```

### Module Details

#### 1. Cloud Run Module (`modules/cloud_run/`)
- **Backend deployment**
  - Memory: 1GB configurable
  - Concurrency: adjustable
  - Minimum instances: 1
  - Maximum instances: auto
  - Timeout: 60 seconds
  - Port: 8080
  
- **Frontend deployment**
  - Static asset serving
  - CDN integration
  - Security headers
  
- **Networking**
  - VPC connector for private SQL/Redis
  - Service account with minimal IAM
  - Environment variables from Secret Manager
  - Health checks configured

#### 2. Cloud SQL Module (`modules/cloud_sql/`)
- **Database**
  - PostgreSQL 15 (latest)
  - High availability (multi-zone)
  - Automated backups (daily)
  - Point-in-time recovery
  - 
- **Security**
  - Private IP only
  - SSL/TLS enforced
  - User authentication with passwords
  - Database initialization scripts
  
- **Monitoring**
  - Slow query logging
  - Connection metrics
  - CPU/memory monitoring

#### 3. Redis Module (`modules/redis/`)
- **Configuration**
  - Redis 7.x latest
  - Memory size: configurable (4GB default)
  - HA mode with replication
  - Automatic failover
  - AOF persistence enabled
  
- **Security**
  - Private IP only
  - VPC connector access
  - AUTH enabled (password from Secret Manager)

#### 4. VPC Module (`modules/vpc_networking/`)
- **Network**
  - Primary subnet (10.0.0.0/20)
  - Cloud Run subnet (10.1.0.0/20)
  - Private service connection
  - NAT gateway for outbound traffic
  
- **Security**
  - Firewall rules (default deny, allow API calls)
  - Service account per workload
  - Network policies enforced

#### 5. IAM Module (`modules/iam/`)
- **Service Accounts**
  - Backend service account (Cloud Run)
  - Database service account (Cloud SQL Proxy)
  - Deployment service account (Terraform)
  
- **Roles**
  - Minimal permission principle
  - Custom roles where needed
  - Cross-project access (if multi-project)
  
- **OIDC**
  - GitHub Actions OIDC provider (future)
  - Workload identity federation configured

## 📊 Terraform Variables

### Environment-Specific (tfvars files)
```hcl
# dev.tfvars
project_id     = "nexus-shield-dev"
region          = "us-central1"
environment     = "dev"
database_size   = "db-custom-1-4096"  # 1CPU, 4GB RAM
redis_size      = "basic"
redis_memory_gb = 1
backend_memory  = 512
replica_count   = 0
```

```hcl
# prod.tfvars
project_id      = "nexus-shield-prod"
region          = "us-central1"
environment     = "prod"
database_size   = "db-custom-2-8192"  # 2CPU, 8GB RAM
redis_size      = "standard"
redis_memory_gb = 4
backend_memory  = 1024
replica_count   = 2
high_availability = true
```

### Global Variables (variables.tf)
- `project_id` - GCP project ID
- `region` - GCP deployment region
- `environment` - Environment name (dev/staging/prod)
- `service_name` - Service prefix for resource naming
- `container_image_backend` - Backend container image URL
- `container_image_frontend` - Frontend container image URL
- `database_version` - PostgreSQL version
- `database_size` - Machine type
- `redis_memory_gb` - Memory allocation
- `enable_ssl` - SSL/TLS enforcement
- `backup_configuration` - Backup settings
- `labels` - Resource labels for billing/organization

## 🔐 Secrets Management

Integration with Cloud Secret Manager:
- Database credentials
- Redis authentication tokens
- JWT secrets
- OAuth provider credentials
- API keys for external services

**Terraform retrieves via**:
```hcl
$PLACEHOLDER
  secret      = "database-password"
  version     = "latest"
}
```

## 📈 Monitoring & Observability

### Cloud Monitoring Integration
- Cloud Run metrics (requests, latency, errors)
- Cloud SQL metrics (connections, query performance)
- Redis metrics (memory usage, eviction rate)
- Custom application metrics (via Prometheus)

### Logging
- Cloud Logging for all services
- Structured logging via application
- Log retention policies (30 days default)

## 🚀 Deployment Strategy

### Phase 2 Sequence (no manual steps)
1. **Planning** - `terraform plan` generates execution plan
2. **Validation** - State consistency checks
3. **Dry Run** - Validates all resources can be created
4. **Apply** - `terraform apply` with auto-approval
5. **Verification** - Health checks post-deploy
6. **Audit Trail** - Immutable JSONL logs of all changes

### Commands

```bash
# Initialize Terraform (download providers, setup backend)
terraform init -backend-config="bucket=$TF_STATE_BUCKET"

# Plan infrastructure changes
terraform plan -var-file=prod.tfvars -out=tfplan

# Apply (auto-approved for CI/CD)
terraform apply -auto-approve tfplan

# Validate state
terraform state list
terraform state show google_cloud_run_service.backend

# Destroy (careful - for cleanup only)
terraform destroy -var-file=dev.tfvars -auto-approve
```

## 🔄 State Management

### Remote State Backend (Cloud Storage)
```hcl
terraform {
  backend "gcs" {
    bucket = "gcp-project-terraform-state"
    prefix = "environment/prod"
  }
}
```

### Immutable Audit Trail
- All state changes logged to JSONL
- State locked during modifications (Terraform native)
- Backup states retained (30 days)
- State versioning enabled

### State Lock Mechanism
- Cloud Datastore (or DynamoDB equivalent)
- Prevents concurrent modifications
- Automatic timeout cleanup

## ✅ Testing Strategy

### Terraform Validation
```bash
# Syntax validation
terraform validate

# Format checking
terraform fmt -check

# Security scanning (tfsec)
tfsec . --minimum-severity=WARNING

# Cost estimation
terraform plan -json | tfjson
```

### Deployment Verification
```bash
# Health checks post-deploy
curl https://${BACKEND_URL}/health
curl https://${BACKEND_URL}/api/v1/status

# Database connectivity
gcloud sql connect postgres --user=root

# Redis connectivity
redis-cli -h ${REDIS_IP} -a ${REDIS_PASSWORD}
```

## 📋 Implementation Checklist

- [ ] Cloud Run module with backend + frontend
- [ ] Cloud SQL module with high availability
- [ ] Redis Memorystore module
- [ ] VPC networking with private endpoints
- [ ] IAM with least privilege
- [ ] Secret Manager integration
- [ ] Remote state backend (GCS)
- [ ] Immutable audit logging for all Terraform operations
- [ ] Terraform validation scripts
- [ ] Deployment verification tests
- [ ] Documentation (module usage, variable reference)
- [ ] Environment-specific tfvars files (dev/staging/prod)
- [ ] Commit to git with immutable tracking

## 🎯 Success Criteria

- ✅ All Terraform modules created and validated
- ✅ `terraform plan` succeeds without errors
- ✅ Infrastructure deployable via `terraform apply`
- ✅ Health checks pass post-deployment
- ✅ All constraints maintained (immutable, ephemeral, idempotent, no-ops)
- ✅ Complete audit trail logged

## 📌 Notes

- **No Manual Infrastructure Changes**: All via Terraform only
- **Immutable Logs**: All `terraform apply` operations logged to JSONL
- **Ephemeral Workspaces**: Child modules support multi-environment
- **Idempotent**: `terraform apply` safe to run multiple times
- **No GitHub Actions**: Direct `terraform` CLI execution only
- **Direct Deployment**: SSH-based post-deployment verification

---

**Created**: March 11, 2026  
**Phase**: 2 of 5  
**Status**: Starting Implementation 🚀
