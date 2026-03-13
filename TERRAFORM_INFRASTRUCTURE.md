# NexusShield Terraform Infrastructure-as-Code

> **Enterprise-Grade Infrastructure Automation**
> 
> Complete Infrastructure-as-Code for production-ready deployment of NexusShield on Google Cloud Platform.

## 📋 Overview

This directory contains **production-grade Terraform configuration** for deploying a complete cloud infrastructure on GCP:

- **🎯 Service Accounts & IAM**: Multi-account setup with least-privilege permissions
- **🌐 VPC Networking**: Private subnets, VPC connectors, NAT gateway, firewall rules
- **🗄️ Cloud SQL**: PostgreSQL 15 with HA, automated backups, private IP
- **💾 Redis Cache**: Memorystore with replication, persistence, authentication
- **🚀 Cloud Run**: Containerized backend and frontend services
- **📦 Storage**: GCS buckets for artifacts, backups, state management
- **🔐 Encryption**: KMS key management for sensitive data

## 🏗️ Architecture

```
Root Configuration (main.tf)
        ↓
    ├── IAM Module        (Service Accounts, Roles, OIDC)
    ├── VPC Module        (Networks, Subnets, NAT, Firewalls)
    ├── Cloud SQL Module  (PostgreSQL HA)
    ├── Redis Module      (Cache Layer)
    ├── Storage Module    (GCS Buckets, KMS)
    └── Cloud Run Module  (Container Services)
```

## 📁 Directory Structure

```
infra/
├── terraform/               # Root Terraform configuration
│   ├── main.tf             # Module orchestration
│   ├── variables.tf        # Input variables
│   ├── outputs.tf          # Output definitions
│   ├── modules/            # Module implementations
│   │   ├── iam/           # Service accounts, roles, OIDC
│   │   ├── vpc_networking/ # VPC, subnets, firewalls, NAT
│   │   ├── cloud_sql/     # PostgreSQL database
│   │   ├── redis/         # Redis cache
│   │   ├── storage/       # GCS buckets, KMS
│   │   └── cloud_run/     # Container services
│   ├── environments/       # Environment-specific configs
│   │   ├── dev.tfvars     # Development (minimal resources)
│   │   ├── staging.tfvars # Staging (HA enabled)
│   │   └── prod.tfvars    # Production (full featured)
│   └── backups/           # Terraform state backups
└── scripts/               # Deployment automation
    ├── terraform-validate.sh
    ├── terraform-deploy.sh
    ├── terraform-destroy.sh
    └── terraform-test.sh
```

## 🚀 Quick Start

### Prerequisites

```bash
# Required tools
brew install terraform        # Terraform CLI
brew install google-cloud-cli # GCP SDK

# Optional but recommended
brew install tfsec            # Security scanning
brew install infracost        # Cost estimation
```

### 1. Configure GCP Project

```bash
# Set default project
gcloud config set project your-gcp-project-id

# Enable required APIs
gcloud services enable compute.googleapis.com
gcloud services enable sqladmin.googleapis.com
gcloud services enable redis.googleapis.com
gcloud services enable run.googleapis.com
gcloud services enable servicenetworking.googleapis.com
gcloud services enable container.googleapis.com
gcloud services enable cloudkms.googleapis.com
gcloud services enable secretmanager.googleapis.com
```

### 2. Configure Environment

Edit the environment file for your target environment:

```bash
# For development
vi infra/terraform/environments/dev.tfvars

# For staging
vi infra/terraform/environments/staging.tfvars

# For production
vi infra/terraform/environments/prod.tfvars
```

**Important:** Do not store passwords directly in tfvars files. Retrieve them from GSM and pass them as variables instead:

```bash
# Example: deploy with GSM credentials
REDIS_PASSWORD=$(gcloud secrets versions access latest --secret=redis-password --project=nexusshield-prod)
DB_PASSWORD=$(gcloud secrets versions access latest --secret=db-password --project=nexusshield-prod)

terraform apply \
  -var="redis_auth_password=$REDIS_PASSWORD" \
  -var="database_root_password=$DB_PASSWORD" \
  -var-file=environments/prod.tfvars
```

**Required parameters in tfvars:**
- `project_id`: Your GCP project ID
- `backend_image`: Container image for backend service
- `frontend_image`: Container image for frontend service
- `redis_auth_password`: Retrieve from GSM: `gcloud secrets versions access latest --secret=redis-password --project=nexusshield-prod`
- `database_root_password`: Retrieve from GSM: `gcloud secrets versions access latest --secret=db-password --project=nexusshield-prod`

**IMPORTANT**: Never hardcode passwords in tfvars files. Always retrieve them from Google Secret Manager (GSM) and pass as environment variables:
```bash
export TF_VAR_redis_auth_password=$(gcloud secrets versions access latest --secret=redis-password --project=nexusshield-prod)
export TF_VAR_database_root_password=$(gcloud secrets versions access latest --secret=db-password --project=nexusshield-prod)
terraform apply -var-file=environments/prod.tfvars
```

### 3. Initialize Terraform

```bash
cd infra/terraform
terraform init \
  -backend-config="bucket=your-state-bucket" \
  -backend-config="prefix=terraform/dev/state"
```

### 4. Validate Configuration

```bash
# Run comprehensive validation
./scripts/terraform-validate.sh dev

# Or manually
cd infra/terraform
terraform validate
terraform plan -var-file=environments/dev.tfvars
```

### 5. Deploy Infrastructure

```bash
# Review and apply changes interactively
./scripts/terraform-deploy.sh dev

# Or with auto-approval
./scripts/terraform-deploy.sh dev --auto-approve
```

## 📊 Module Reference

### IAM Module
**Purpose**: Service accounts, custom roles, Workload Identity Federation

**Resources**:
- 3 Service Accounts (backend, frontend, terraform)
- 2 Custom Roles (cloud_sql_proxy, secret_reader)
- Workload Identity Pool & Provider
- 10+ IAM bindings

**Location**: `modules/iam/`

### VPC Networking Module
**Purpose**: Private network infrastructure, service connectivity

**Resources**:
- VPC Network
- 2 Subnets (primary database, Cloud Run connector)
- VPC Connector (for private service access)
- Cloud Router & NAT Gateway
- 4 Firewall Rules
- Private Service Connection

**Location**: `modules/vpc_networking/`

### Cloud SQL Module
**Purpose**: PostgreSQL database with HA, backups, SSL

**Resources**:
- Primary Cloud SQL Instance (PostgreSQL 15)
- HA Replica (multi-zone)
- Automated Backups (point-in-time recovery)
- Database & Users
- Query Insights, Slow Query Logs

**Location**: `modules/cloud_sql/`
**Default Machine**: `db-custom-1-4096` (1 vCPU, 4GB RAM)

### Redis Module
**Purpose**: In-memory cache with HA and persistence

**Resources**:
- Redis Instance (7.x)
- Standard Tier (replication)
- RDB Persistence
- AUTH Password
- Maintenance Window
- Monitoring & Alerting

**Location**: `modules/redis/`
**Default Memory**: 4GB

### Storage Module
**Purpose**: Artifact storage, state backend, backups

**Resources**:
- 4 GCS Buckets (state, artifacts, backups, audit logs)
- KMS Key Ring & Crypto Key
- Lifecycle Rules (auto-delete)
- Bucket IAM Bindings
- Encryption at Rest

**Location**: `modules/storage/`

### Cloud Run Module
**Purpose**: Containerized service deployment

**Resources**:
- Backend Service (API)
- Frontend Service (Web UI)
- VPC Connector Integration
- IAM Bindings
- Health Checks
- Autoscaling Configuration

**Location**: `modules/cloud_run/`

## 📝 Variable Reference

### Key Variables

```hcl
# Project
project_id          = "your-gcp-project-id"
region              = "us-central1"
environment         = "dev"  # dev, staging, prod

# Container Images (REQUIRED)
backend_image  = "gcr.io/project/backend:latest"
frontend_image = "gcr.io/project/frontend:latest"

# Compute
backend_memory              = "1Gi"      # CPU cores: 1
frontend_memory             = "512Mi"    # CPU cores: 1
cloud_run_min_instances     = 1
cloud_run_max_instances     = 10

# Database
database_machine_type       = "db-custom-1-4096"
database_version            = "15"
enable_database_ha          = true
backup_location             = "us"

# Cache
redis_tier                  = "standard"
redis_memory_size_gb        = 4
redis_version               = "7.x"

# Security
enable_encryption           = true
enable_wif                  = true
enable_nat_gateway          = true

# Secrets (REQUIRED, use sensitive = true)
redis_auth_password         = ""  # Set from GSM: $(gcloud secrets versions access latest --secret=redis-password)
database_root_password      = ""  # Set from GSM: $(gcloud secrets versions access latest --secret=db-password)
```

## 🔧 Deployment Scripts

### Validate Configuration
```bash
./scripts/terraform-validate.sh [dev|staging|prod]
```
- Checks syntax
- Validates variable requirements
- Creates plan without applying
- Runs security scanning (tfsec)

### Deploy Infrastructure
```bash
./scripts/terraform-deploy.sh [dev|staging|prod] [--auto-approve]
```
- Backs up current state
- Creates deployment plan
- Applies changes
- Exports deployment outputs

### Run Tests
```bash
./scripts/terraform-test.sh [dev|staging|prod]
```
- Validates module structure
- Checks variable definitions
- Tests syntax across all modules
- Verifies formatting

### Destroy Infrastructure
```bash
./scripts/terraform-destroy.sh [dev|staging|prod] [--auto-approve]
```
- Backs up state before deletion
- Destroys all managed resources

## 📋 Environments

### Development Environment
- Minimal resource allocation
- Single-zone database (no HA)
- Basic tier Redis (no replication)
- Cost-optimized
- Autoscaling: 0-3 instances

```bash
./scripts/terraform-deploy.sh dev
```

### Staging Environment
- Medium resource allocation
- Multi-zone database with HA
- Standard tier Redis
- Complete HA setup
- Autoscaling: 1-5 instances

```bash
./scripts/terraform-deploy.sh staging
```

### Production Environment
- Large resource allocation
- Multi-zone HA with automated failover
- Standard tier Redis with replication
- Full monitoring and backups
- Autoscaling: 2-20 instances
- All security features enabled

```bash
./scripts/terraform-deploy.sh prod
```

## 🔐 Security Features

### Encryption
- **KMS**: Cloud KMS encryption for storage buckets
- **TLS**: SSL/TLS enforced on Cloud SQL
- **Auth**: Redis AUTH password required
- **IAM**: Least-privilege service accounts

### Network Security
- **Private IP**: All databases private-only
- **VPC Connector**: Secure private service access
- **Firewall Rules**: Default deny-all, explicit allows
- **NAT**: Outbound through NAT gateway

### Credentials
- **No Hardcoding**: All secrets via variables
- **Sensitive Output**: Passwords marked as sensitive
- **Secret Manager Ready**: Integration points included
- **Workload Identity**: GitHub Actions OIDC support

## 📊 Monitoring & Observability

### Cloud SQL
- Cloud SQL Insights enabled
- Slow query logging
- Query Insights for performance analysis
- Automated backups with PITR

### Redis
- Monitoring & metrics in Cloud Monitoring
- Custom alerts for CPU/memory
- Persistence enabled (RDB snapshots)
- Maintenance windows scheduled

### Cloud Run
- Cloud Logging integration
- Request/response metrics
- Container logs streaming
- Health checks (startup & liveness)

## 🆘 Troubleshooting

### Terraform Validation Fails
```bash
# Fix formatting
terraform fmt -recursive

# Re-validate
terraform -chdir=infra/terraform validate
```

### Provider Authentication
```bash
# Authenticate with GCP
gcloud auth application-default login

# Set project
gcloud config set project your-gcp-project-id
```

### State Lock Issues
```bash
# Check current locks
terraform force-unlock <LOCK_ID>

# View state
terraform state list
terraform state show <resource>
```

### Incomplete Deployments
```bash
# Backup current state and destroy
cp terraform.tfstate terraform.tfstate.backup
terraform destroy -var-file=environments/ENVIRONMENT.tfvars

# Redeploy
terraform apply -var-file=environments/ENVIRONMENT.tfvars
```

## 📈 Cost Estimation

Use Infracost for cost estimates:

```bash
# Install infracost
brew install infracost

# Show cost estimate
infracost breakdown --path infra/terraform/terraform.tfplan

# Compare costs across environments
infracost diff --path plan-dev.tfplan
```

## 🔄 State Management

### Remote State Backend
- **Location**: GCS bucket
- **Encryption**: KMS-encrypted
- **Versioning**: Enabled
- **Access**: Via service account

### State Backups
```bash
# Manual backup
cp terraform.tfstate terraform.tfstate.backup

# Restore from backup
cp terraform.tfstate.backup terraform.tfstate
terraform refresh
```

## 🎓 Best Practices

1. **Always Validate First**: Run validate before deploy
2. **Review Plans**: Always review `terraform plan` output
3. **One Environment at a Time**: Deploy to dev → staging → prod
4. **Backup State**: Regular state backups before changes
5. **Test Destruction**: Regularly test destroy/recreate cycle
6. **Lock State**: Use state locking for team deployments
7. **Version Modules**: Use versioning for production stability

## 📚 Additional Resources

- [Terraform Documentation](https://www.terraform.io/docs)
- [Google Provider Docs](https://registry.terraform.BASE64_BLOB_REDACTED)
- [GCP Best Practices](https://cloud.google.com/docs/terraform/best-practices)
- [Infrastructure as Code Guide](https://www.terraform.io/cloud-docs)

## 📞 Support

For issues or questions:
1. Check Terraform logs: `terraform plan -var-file=...`
2. Review GCP console for resource details
3. Check Cloud Logging for runtime errors
4. Consult module-specific README files

---

**Last Updated**: March 11, 2026
**Terraform Version**: >= 1.0
**Provider Version**: google ~> 5.0
