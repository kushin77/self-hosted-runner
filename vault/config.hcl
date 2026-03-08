# Vault Configuration for GitHub Actions CI/CD
# This file defines auth methods, secret engines, and policies for GitOps

# Enable GitHub JWT auth method
path "auth/jwt/config" {
  capabilities = ["create", "read", "update", "delete"]
}

path "auth/jwt/login/*" {
  capabilities = ["create", "read"]
}

# GitHub Actions OIDC role
path "auth/jwt/role/github-actions" {
  capabilities = ["create", "read", "update", "delete"]
}

# AWS dynamic credentials
path "aws/config/root" {
  capabilities = ["create", "read", "update", "delete"]
}

path "aws/roles/github-role" {
  capabilities = ["create", "read", "update", "delete"]
}

path "aws/creds/github-role" {
  capabilities = ["create", "read"]
}

# GCP dynamic credentials
path "gcp/config" {
  capabilities = ["create", "read", "update", "delete"]
}

path "gcp/roleset/github-sa" {
  capabilities = ["create", "read", "update", "delete"]
}

path "gcp/key/github-sa" {
  capabilities = ["create", "read", "update", "delete"]
}

# Terraform backend credentials
path "secret/data/terraform/backend" {
  capabilities = ["create", "read", "update", "delete"]
}

# Terraform AWS credentials
path "secret/data/terraform/aws" {
  capabilities = ["create", "read", "update"]
}

# Terraform GCP credentials
path "secret/data/terraform/gcp" {
  capabilities = ["create", "read", "update"]
}

# PKI (optional - for certificate rotation)
path "pki/issue/github-*" {
  capabilities = ["create", "read"]
}

path "pki/certs" {
  capabilities = ["list"]
}

# Audit logs
path "sys/audit" {
  capabilities = ["read"]
}

# Replication status
path "sys/replication/status" {
  capabilities = ["read"]
}

# Lease management
path "sys/leases/renew" {
  capabilities = ["update"]
}

path "sys/leases/revoke" {
  capabilities = ["update"]
}

---
# Vault Configuration Block (HCL)

# GitHub OIDC JWT Auth Configuration
auth_method "jwt" {
  path = "auth/jwt"
  
  # Configuration
  config = {
    oidc_discovery_url = "https://token.actions.githubusercontent.com"
    oidc_client_id     = "sts.github.actions"
    default_role       = "github-actions"
  }
  
  # GitHub Actions role
  role "github-actions" {
    bound_audiences      = ["sts.github.actions"]
    user_claim           = "actor"
    role_type            = "jwt"
    policies             = ["github-actions"]
    ttl                  = "1h"
    max_ttl              = "1h"
    
    bound_claims = {
      repository = "kushin77/self-hosted-runner"
    }
  }
}

# AWS Credential Engine
secret_engine "aws" {
  path = "aws"
  
  config = {
    access_key = "AWS_ACCESS_KEY_ID"           # Set from environment
    secret_key = "AWS_SECRET_ACCESS_KEY"       # Set from environment
    region     = "us-east-1"
  }
  
  role "github-role" {
    credential_type = "assumed_role"
    role_arns       = ["arn:aws:iam::ACCOUNT_ID:role/vault-github-role"]
    ttl             = "1h"
    max_ttl         = "6h"
  }
}

# GCP Credential Engine
secret_engine "gcp" {
  path = "gcp"
  
  config = {
    credentials = file("${path.module}/gcp-service-account.json")
    project_id = "YOUR_GCP_PROJECT"
  }
  
  roleset "github-sa" {
    service_account = "vault-github@YOUR_GCP_PROJECT.iam.gserviceaccount.com"
    secret_type     = "service_account_key"
    bindings = {
      "roles/iam.serviceAccountUser" = [
        "resource.matchTag('env', 'github')"
      ]
    }
    ttl = "1h"
  }
}

# KV Secret Engine (for static secrets)
secret_engine "kv" {
  path    = "secret"
  version = 2
}

# PKI (optional - for certificate-based auth)
secret_engine "pki" {
  path = "pki"
  
  config = {
    ttl             = "768h"
    max_lease_ttl   = "768h"
  }
  
  role "github-cert" {
    allowed_domains  = ["selfhosted-runner.example.com"]
    allow_subdomains = true
    ttl              = "72h"
  }
}

# Audit logging (required)
audit "file" {
  path = "/var/log/vault/audit.log"
  
  options = {
    file_path = "/var/log/vault/audit.log"
    hmac_accessor = "false"
  }
}

audit "syslog" {
  path = "syslog/"
  
  options = {
    facility = "LOCAL0"
    tag      = "vault"
  }
}

# Entity aliases for audit trail
entity_alias_factory {
  auth_method = "jwt"
  
  aliases = {
    github_user = {
      claim = "actor"
      format = "user-{{value}}"
    }
    
    github_repo = {
      claim = "repository"
      format = "repo-{{value}}"
    }
  }
}

---
# Vault Secrets Structure (directory layout)

secret/
├── data/
│   ├── terraform/
│   │   ├── backend/          # Terraform backend credentials
│   │   ├── aws/              # Terraform AWS credentials
│   │   └── gcp/              # Terraform GCP credentials
│   ├── github/
│   │   ├── actions/          # GitHub Actions secrets
│   │   └── deployment/       # Deployment secrets
│   └── application/          # Application-specific secrets

aws/
├── creds/github-role/        # Dynamic AWS credentials
└── config/                   # AWS configuration

gcp/
├── key/github-sa/            # Dynamic GCP service account keys
└── config/                   # GCP configuration

pki/
├── issue/github-*/           # Certificate issuance
└── roles/                    # Certificate roles

---
# Required GitHub Secrets Configuration

VAULT_ADDR: https://vault.example.com:8200
VAULT_NAMESPACE: admin
VAULT_ROLE: github-actions
VAULT_JWT_AUDIENCE: sts.github.actions

KMS_KEY_ID: arn:aws:kms:us-east-1:ACCOUNT_ID:key/KEY_ID
KMS_ENCRYPTION_ENABLED: true

AWS_ROLE_ARN: arn:aws:iam::ACCOUNT_ID:role/github-terraform-oidc-role
AWS_SESSION_DURATION: 3600

GCP_WORKLOAD_IDENTITY_PROVIDER: projects/PROJECT_NUM/locations/global/workloadIdentityPools/github-pool/providers/github-provider
GCP_SERVICE_ACCOUNT_EMAIL: github-terraform-sa@PROJECT_ID.iam.gserviceaccount.com
GCP_PROJECT_ID: YOUR_GCP_PROJECT
