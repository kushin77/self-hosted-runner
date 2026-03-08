# Configuration Guide & Index

**Last Updated**: March 7, 2026  
**Status**: ⚙️ Complete Configuration Catalog  
**Purpose**: Single reference for all configuration files, settings, and environment variables

---

## Quick Navigation

- [Configuration Files](#configuration-files) - All `.yml`, `.env`, `.json` configs
- [Environment Variables](#environment-variables) - By category
- [GitHub Settings](#github-settings) - Repository configuration
- [Build & Runtime Config](#build--runtime-configuration) - Compilation, execution
- [Cloud Configuration](#cloud-configuration) - AWS, GCP, Terraform
- [Quick Reference](#quick-reference) - Copy-paste snippets

---

## Configuration Files

### **Workflow Configuration**

| File | Purpose | Type | Env | Location |
|------|---------|------|-----|----------|
| `.github/workflows/*.yml` | All 197 CI/CD workflows | YAML | All | `.github/workflows/` |
| `.github/codeowners` | Code review owners | Text | All | `.github/` |
| `.github/dependabot.yml` | Dependabot configuration | YAML | All | `.github/` |
| `.github/CODEOWNERS` | PR review rules | Text | All | `.github/` |
| `.pre-commit-config.yaml` | Pre-commit hooks | YAML | Local dev | Root |

---

### **Repository Configuration**

| File | Purpose | Type | Env | Location |
|------|---------|------|-----|----------|
| `.gitlab-ci.yml` | GitLab CI configuration | YAML | GitLab | Root |
| `.gitignore` | Git ignore patterns | Text | All | Root |
| `.gitattributes` | Git attributes | Text | All | Root |
| `CODEOWNERS` | Code review assignments | Text | All | Root |
| `renovate.json` | Renovate bot config | JSON | All | Root |

---

### **Docker Configuration**

| File | Purpose | Type | Env | Location |
|------|---------|------|-----|----------|
| `Dockerfile` | Main image build | Dockerfile | All | Root |
| `Dockerfile.backup` | Backup image config | Dockerfile | All | Root |
| `docker-compose.yml` | Local dev services | YAML | Local dev | Root |
| `.dockerignore` | Docker ignore patterns | Text | All | Root |

---

### **Build & Compilation**

| File | Purpose | Type | Env | Location |
|------|---------|------|-----|----------|
| `Makefile` | Build targets/tasks | Make | All | Root |
| `package.json` | Node.js dependencies | JSON | Node/web | Root |
| `go.mod` / `go.sum` | Go dependencies | Go modules | Go | (if applicable) |
| `requirements.txt` | Python dependencies | Text | Python | Root |
| `build.gradle` | Gradle build config | Gradle | Java | (if applicable) |

---

### **Terraform Configuration**

| File | Purpose | Type | Env | Location |
|------|---------|------|-----|----------|
| `terraform/main.tf` | Primary resource config | Terraform | AWS/GCP | `terraform/` |
| `terraform/*.tf` | Additional resources | Terraform | AWS/GCP | `terraform/` |
| `terraform/terraform.tfvars` | Variable defaults | HCL | All | `terraform/` |
| `terraform/.terraform.lock.hcl` | Terraform lock file | HCL | All | `terraform/` |
| `terraform/backend.tf` | State backend config | Terraform | AWS S3 | `terraform/` |

---

### **Cloud Configuration**

| File | Purpose | Type | Env | Location |
|------|---------|------|-----|----------|
| `k8s/*.yaml` | Kubernetes manifests | YAML | K8s | `k8s/` |
| `terraform/aws/*.tf` | AWS infrastructure | Terraform | AWS | `terraform/aws/` |
| `terraform/gcp/*.tf` | GCP infrastructure | Terraform | GCP | `terraform/gcp/` |
| `docker-compose.yml` | Local dev compose | YAML | Local | Root |

---

### **Application Configuration**

| File | Purpose | Type | Env | Location |
|------|---------|------|-----|----------|
| `.env` | Local secrets (dev only) | Bash | Local dev | Root (GITIGNORE'd) |
| `config/app.yml` | Application config | YAML | All | `config/` |
| `config/database.yml` | Database config | YAML | All | `config/` |
| `config/logging.yml` | Logging configuration | YAML | All | `config/` |
| `config/security.yml` | Security settings | YAML | All | `config/` |

---

## Environment Variables

### **Required (Must Be Set)**

| Variable | Purpose | Value Example | Scope | How to Set |
|----------|---------|---------------|-------|-----------|
| `AWS_REGION` | AWS region | `us-east-1` | Terraform | GitHub secret / Terraform var |
| `GCP_PROJECT_ID` | GCP project | `gcp-eiq` | GCP | GitHub secret / env var |
| `GITHUB_TOKEN` | GitHub API access | `ghp_...` | Workflows | GitHub secret (default) |
| `DEPLOY_SSH_KEY` | SSH private key | PEM key | Runners | GitHub secret |

---

### **Optional (Enhance Functionality)**

| Variable | Purpose | Default | Scope | How to Set |
|----------|---------|---------|-------|-----------|
| `AWS_OIDC_ROLE_ARN` | Assume AWS role | Not set | Terraform | GitHub secret |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | GCP OIDC provider | Not set | GCP | GitHub secret |
| `MINIO_ENDPOINT` | MinIO server | Not set | Artifact storage | GitHub secret |
| `VAULT_ADDR` | Vault server | `https://vault...` | Secrets | GitHub secret |
| `LOG_LEVEL` | Logging verbosity | `info` | All | Environment / config file |
| `TIMEOUT` | Operation timeout | `300` | Scripts | Environment / argument |

---

### **System Variables (Auto-Set By GitHub/Runners)**

| Variable | Purpose | Value | Source |
|----------|---------|-------|--------|
| `GITHUB_WORKSPACE` | Checkout directory | `/home/runner/work/...` | GitHub Actions |
| `GITHUB_RUN_ID` | Workflow run ID | Numeric ID | GitHub Actions |
| `GITHUB_SHA` | Commit SHA | `abc123...` | GitHub Actions |
| `GITHUB_REF` | Git ref (branch/tag) | `refs/heads/main` | GitHub Actions |
| `RUNNER_OS` | Operating system | `Linux` | Github Actions |

---

### **By Component**

#### **AWS Configuration**
```bash
AWS_REGION=us-east-1
AWS_ACCOUNT_ID=123456789012
AWS_OIDC_ROLE_ARN=arn:aws:iam::123456789012:role/github-actions-terraform
AWS_ACCESS_KEY_ID=AKIA...  # If not using OIDC
AWS_SECRET_ACCESS_KEY=...   # If not using OIDC
```

#### **GCP Configuration**
```bash
GCP_PROJECT_ID=gcp-eiq
GCP_WORKLOAD_IDENTITY_PROVIDER=projects/123456789/locations/global/workloadIdentityPools/github-actions/providers/github
GCP_SERVICE_ACCOUNT_EMAIL=github-actions-terraform@gcp-eiq.iam.gserviceaccount.com
GCP_WORKLOAD_IDENTITY_SERVICE_ACCOUNT=github-actions-terraform@gcp-eiq.iam.gserviceaccount.com
```

#### **MinIO Configuration**
```bash
MINIO_ENDPOINT=https://minio.example.com
MINIO_ACCESS_KEY=minioadmin
MINIO_SECRET_KEY=...
MINIO_BUCKET=artifacts
MINIO_USE_SSL=true
```

#### **Vault Configuration**
```bash
VAULT_ADDR=https://vault.example.com
VAULT_NAMESPACE=github
VAULT_ROLE_ID=auth/approle/role/github-actions/role-id
VAULT_SECRET_ID=auth/approle/role/github-actions/secret-id
```

#### **Logging & Monitoring**
```bash
LOG_LEVEL=info          # debug, info, warn, error
LOG_FORMAT=json         # json, text
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
PROMETHEUS_PUSHGATEWAY=http://localhost:9091
```

---

## GitHub Settings

### **Repository Settings**

**Branch Protection** (`Settings → Branches → main`)
- Require pull request reviews: ✅ Yes (1+ approvals)
- Require status checks to pass: ✅ Yes
- Require up-to-date branches before merging: ✅ Yes
- Include administrators: ❌ No (ops can override)
- Restrict who can push: ✅ Yes

**Advanced** (`Settings → Code and automation → Rulesets`)
- Workflow file access: Restricted
- Artifact retention: 30 days
- Secret scanning: ✅ Enabled

---

### **Secrets Configuration**

**Repository Secrets** (`Settings → Secrets and variables → Actions`)

```bash
# Command to list
gh secret list --repo kushin77/self-hosted-runner

# Command to set
gh secret set SECRET_NAME --repo kushin77/self-hosted-runner < /path/to/secret

# Command to delete
gh secret delete SECRET_NAME --repo kushin77/self-hosted-runner
```

See: **[SECRETS_INDEX.md](SECRETS_INDEX.md)** for all secrets

---

### **Environments**

**Available GitHub Environments:**
- `production` - Production deployment environment
- `staging` - Staging/test environment  
- `development` - Local development

**Environment Protection Rules:**
- Production requires approval before deployment
- Staging auto-deploys on PR merge to staging branch
- Development needs no approval

---

### **Actions Settings**

| Setting | Value | Purpose |
|---------|-------|---------|
| Workflows can read/write | ✅ Enabled | Scripts need to modify repo |
| Create pull requests | ⭕ Limited | Only specific workflows |
| Workflow permissions | Read/Write | Default for all workflows |

---

## Build & Runtime Configuration

### **Docker Build Args**

```dockerfile
ARG BASE_IMAGE=ubuntu:22.04
ARG PYTHON_VERSION=3.11
ARG NODE_VERSION=18.x
ARG GO_VERSION=1.21
```

### **Terraform Variables**

**File:** `terraform/terraform.tfvars`

```hcl
aws_region              = "us-east-1"
aws_account_id          = "123456789012"
environment             = "production"
instance_type           = "t3.xlarge"
desired_capacity        = 3
max_capacity           = 10
enable_auto_scaling    = true
enable_spot_instances  = true
```

### **Application Runtime Config**

**File:** `config/app.yml`

```yaml
server:
  port: 8080
  timeout: 30s
  
database:
  host: localhost
  port: 5432
  pool_size: 20
  
logging:
  level: info
  format: json
  
security:
  tls_enabled: true
  min_tls_version: 1.3
```

---

## Cloud Configuration

### **AWS Configuration**

**Region:** `us-east-1`

**Key Services:**
- EC2 (compute)
- ElastiCache (caching)
- S3 (artifact storage)
- DynamoDB (state lock)
- ECR (container registry)
- STS (OIDC/assume role)

**See:** `terraform/aws/` for IaC

---

### **GCP Configuration**

**Project:** `gcp-eiq`

**Key Services:**
- GKE (Kubernetes)
- Cloud Run (serverless)
- Secret Manager (GSM)
- Workload Identity (OIDC)
- Cloud Storage (artifact storage)

**See:** `terraform/gcp/` for IaC

---

### **Kubernetes Configuration**

**Cluster Config:** `k8s/kube-config.yaml` (not in repo, local-only)

**Manifests:**
```
k8s/
├── namespace/
├── deployments/
├── services/
├── configmaps/
├── secrets/              # ⚠️  NO SECRETS - Use Vault/GCP GSM
└── ingress/
```

---

## Quick Reference

### **Common Environment Variable Setups**

**For Local Development:**
```bash
export AWS_REGION=us-east-1
export GCP_PROJECT_ID=gcp-eiq
export LOG_LEVEL=debug
export TIMEOUT=600
```

**For CI/CD (via GitHub secrets):**
```bash
# Set via:
gh secret set AWS_REGION --repo kushin77/self-hosted-runner
gh secret set GCP_PROJECT_ID --repo kushin77/self-hosted-runner
# etc.
```

**For Terraform:**
```bash
export TF_VAR_aws_region=us-east-1
export TF_VAR_environment=production
```

---

### **Common Configuration Commands**

```bash
# List all environment variables
printenv | sort

# Check GitHub secret for typos (without revealing value)
gh secret list --repo kushin77/self-hosted-runner | grep PATTERN

# Validate configuration file syntax
terraform validate
docker build --dry-run .
python -m py_compile script.py

# Check configuration against schema
yamllint .github/workflows/*.yml
jsonlint config/*.json
```

---

### **Debugging Configuration Issues**

```bash
# Show configuration values (safe)
terraform show -json | jq '.values' | head -20

# Check which config file is being used
config_file=$(find . -name "*.yml" | grep app | grep -v workflows | head -1)
echo "Using config: $config_file"

# Validate configuration access
test -r "$config_file" && echo "Readable" || echo "NOT readable"
```

---

## Related Documentation

- **[SECRETS_INDEX.md](SECRETS_INDEX.md)** — Secret configuration details
- **[CONTRIBUTING.md](CONTRIBUTING.md)** — Configuration change procedures
- **[WORKFLOWS_INDEX.md](WORKFLOWS_INDEX.md)** — Workflows using config
- **[SCRIPTS_REGISTRY.md](SCRIPTS_REGISTRY.md)** — Scripts reading config
- **[docs/AWS_OIDC_SETUP.md](docs/AWS_OIDC_SETUP.md)** — AWS OIDC configuration
- **[GSM_AWS_CREDENTIALS_QUICK_START.md](GSM_AWS_CREDENTIALS_QUICK_START.md)** — GSM setup

---

## Checklist: Environment Setup

**Before running any workflow:**
- [ ] AWS region set: `export AWS_REGION=us-east-1`
- [ ] GCP project set: `export GCP_PROJECT_ID=gcp-eiq`
- [ ] GitHub token available: `echo $GITHUB_TOKEN` (non-empty)
- [ ] Secrets configured: `bash scripts/audit-secrets.sh --validate`
- [ ] Configuration readable: `test -r config/app.yml && echo OK`
- [ ] Terraform initialized: `terraform init` (one-time)
- [ ] Credentials working: `aws sts get-caller-identity` or `gcloud auth list`

---

*Last Updated: March 7, 2026*  
*Maintained by: DevOps & Infrastructure Team*  
*Next Review: June 7, 2026*
