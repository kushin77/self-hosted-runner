# Complete Deployment Guide — Chaos Testing Framework

## Overview

This guide provides step-by-step instructions to deploy and operate the chaos testing framework with immutable audit logs, ephemeral credentials, idempotent execution, fully automated hands-off operations, and no GitHub Actions.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ Hardened Self-Hosted Runner (non-root, dedicated user)           │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Cron: 0 3 * * * /run-all-chaos-tests.sh (with cred fetch)     │
│         ↓                                                        │
│  scripts/ops/fetch_credentials.sh                              │
│    → Try GSM → Try Vault → Try KMS (failover)                  │
│    → Export AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY            │
│         ↓                                                        │
│  scripts/testing/run-all-chaos-tests.sh                        │
│    → Execute all chaos test suites                             │
│    → Write append-only JSONL audit logs                        │
│         ↓                                                        │
│  scripts/ops/upload_jsonl_to_s3.sh                             │
│    → Upload logs to immutable S3 bucket (Object Lock)          │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Prerequisites

- Linux host (Debian/Ubuntu/RHEL recommended)
- sudo access
- Git installed
- One of: gcloud CLI (GSM), vault CLI (Vault), or AWS CLI (KMS)
- Public key for SSH auth
- S3 bucket with Object Lock enabled (optional but recommended)

## Step 1: Prepare AWS Credentials

### Option A: Google Secret Manager (GSM)

```bash
# Create secret with AWS credentials (format: ACCESS_KEY:SECRET_KEY:SESSION_TOKEN)
gcloud secrets create aws-chaos-credentials \
  --replication-policy="automatic" \
  --data-file=- <<EOF
AKIA_REDACTED:BASE64_BLOB_REDACTED:AQoDYXdzEJr...
EOF
```

### Option B: HashiCorp Vault

```bash
vault kv put secret/aws/chaos credentials="AKIA_REDACTED:BASE64_BLOB_REDACTED:AQoDYXdzEJr..."
```

### Option C: AWS KMS

```bash
# Encrypt credentials and place at /etc/secrets/aws-credentials.kms
echo -n "AKIA_REDACTED:BASE64_BLOB_REDACTED:AQoDYXdzEJr..." | \
  aws kms encrypt --key-id "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000" \
  --plaintext fileb:///dev/stdin \
  --output text --query CiphertextBlob > /etc/secrets/aws-credentials.kms
```

## Step 2: Provision Hardened Runner

```bash
# Download and run the automated installer
sudo curl -fsSL https://raw.githubusercontent.com/kushin77/self-hosted-runner/main/scripts/ops/install_hardened_runner.sh \
  -o /tmp/install_runner.sh
sudo bash /tmp/install_runner.sh
```

Or, manually:

```bash
# Create runner user and directories
sudo useradd -m -s /bin/bash runner
sudo mkdir -p /opt/runner /var/log/chaos
sudo chown runner:runner /opt/runner /var/log/chaos

# Clone repository
sudo -u runner git clone https://github.com/kushin77/self-hosted-runner /opt/runner/repo

# Set up SSH (paste public key here)
sudo -u runner mkdir -p /opt/runner/.ssh
sudo -u runner chmod 700 /opt/runner/.ssh
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK..." | \
  sudo tee /opt/runner/.ssh/authorized_keys
sudo -u runner chmod 600 /opt/runner/.ssh/authorized_keys
```

## Step 3: Configure Credentials

Set environment variables for credential fetching:

```bash
# For GSM:
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account.json"

# For Vault:
export VAULT_ADDR="https://vault.example.com:8200"
export VAULT_TOKEN="s.xxxxxxxxxx"

# For KMS:
export AWS_REGION="us-east-1"
```

## Step 4: Set Up Cron Job

```bash
# Create cron job (runs daily at 03:00 UTC)
sudo crontab -u runner -e

# Add this line:
0 3 * * * /bin/bash -lc 'source /opt/runner/repo/scripts/ops/fetch_credentials.sh && /opt/runner/repo/scripts/testing/run-all-chaos-tests.sh' >> /var/log/chaos/orchestrator-$(date +\%F).log 2>&1
```

Or use the installer:

```bash
CRON_SCHEDULE="0 3 * * *" sudo bash /tmp/install_runner.sh
```

## Step 5: Verify Setup

### Test credential fetcher:

```bash
sudo -u runner bash -c 'source /opt/runner/repo/scripts/ops/fetch_credentials.sh && env | grep AWS_'
```

### Run chaos tests manually:

```bash
sudo -u runner bash -c '/opt/runner/repo/scripts/testing/run-all-chaos-tests.sh'
```

### Check log output:

```bash
tail -f /var/log/chaos/orchestrator-$(date +%F).log
```

## Step 6: Configure Immutable Log Storage

### Create S3 bucket with Object Lock:

```bash
aws s3api create-bucket \
  --bucket chaos-forensic-logs \
  --region us-east-1 \
  --object-lock-enabled-for-bucket

# Enable default retention (30 days, GOVERNANCE mode)
aws s3api put-object-lock-legal-hold \
  --bucket chaos-forensic-logs \
  --key "logs/" \
  --object-lock-legal-hold-status ON
```

### Configure uploader credentials:

```bash
# Set S3 bucket and credentials for uploader
cat >> /home/runner/.bash_profile <<EOF
export S3_BUCKET="chaos-forensic-logs"
export S3_PREFIX="chaos-logs"
export LOG_DIR="/opt/runner/repo/reports/chaos"
EOF
```

### Add uploader to cron (runs after chaos tests):

```bash
# Append to runner crontab:
5 3 * * * /bin/bash -lc 'source /opt/runner/repo/scripts/ops/fetch_credentials.sh && /opt/runner/repo/scripts/ops/upload_jsonl_to_s3.sh' >> /var/log/chaos/uploader-$(date +\%F).log 2>&1
```

## Step 7: Monitor and Verify

### Check cron logs:

```bash
sudo -u runner crontab -l
sudo journalctl -u cron -f
```

### Inspect audit logs:

```bash
cat /opt/runner/repo/reports/chaos/*.jsonl | jq .
```

### Verify S3 uploads:

```bash
aws s3 ls s3://chaos-forensic-logs/chaos-logs/
```

## Security Hardening Checklist

- [ ] Runner user has no sudo access (principle of least privilege)
- [ ] SSH key-based auth only (no passwords)
- [ ] Credentials fetched at runtime from GSM/Vault/KMS (not hardcoded)
- [ ] JSONL logs appended to (immutable audit trail)
- [ ] S3 logs stored with Object Lock enabled
- [ ] Cron job runs as non-root `runner` user
- [ ] Repository policy enforced (no GitHub Actions)
- [ ] Logs rotated and archived daily

## Troubleshooting

### Cron job not running
```bash
# Check cron daemon
sudo systemctl status cron
# Check cron logs
sudo journalctl -u cron -n 50
# Verify crontab entry
sudo crontab -u runner -l
```

### Credential fetch failing
```bash
# Test GSM
gcloud secrets versions access latest --secret="aws-chaos-credentials"
# Test Vault
vault kv get secret/aws/chaos
# Test KMS
aws kms decrypt --ciphertext-blob fileb:///etc/secrets/aws-credentials.kms --region us-east-1
```

### S3 upload permission denied
```bash
# Verify IAM role/user has s3:PutObject permission
aws iam get-user-policy --user-name chaos-uploader --policy-name allow-s3-upload
```

## Cleanup and Rollback

To disable the chaos tests:

```bash
# Remove cron jobs
sudo crontab -u runner -e # and remove entries

# Optionally archive runner home
sudo tar czf /archive/runner-$(date +%F).tar.gz -C /opt runner/

# Delete runner user
sudo userdel -r runner
```

## References

- Chaos Testing Framework: `scripts/testing/`
- Credential Fetcher: `scripts/ops/fetch_credentials.sh`
- Log Uploader: `scripts/ops/upload_jsonl_to_s3.sh`
- Runner Installer: `scripts/ops/install_hardened_runner.sh`
- Policy: `POLICIES/NO_GITHUB_ACTIONS.md`
- Runbook: `RUNBOOKS/HARDENED_RUNNER_ONBOARDING.md`
- Cron Guide: `DEPLOYMENT/cron/chaos-cron.md`
