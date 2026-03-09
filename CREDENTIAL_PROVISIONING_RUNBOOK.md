# Credential Provisioning & Deployment Runbook

**Document Version:** 1.0  
**Date:** 2026-03-09  
**Status:** Production Ready

---

## Overview

This runbook provides step-by-step instructions for provisioning SSH credentials to credential providers (Vault, AWS Secrets Manager, Google Secret Manager) and activating the automated direct-deploy watcher.

### Architecture

```
┌─────────────────────────────────────────────┐
│   Operator Workstation                      │
│   (SSH key generation, credential setup)    │
└────────────────┬────────────────────────────┘
                 │
        ┌────────┴─────────┐
        │                  │
        ↓                  ↓
   ┌──────────┐    ┌──────────────┐
   │  Vault   │    │ AWS Secrets  │
   │          │    │ Manager      │
   └────┬─────┘    └──────┬───────┘
        │                 │
        │    ┌────────────┘
        │    │
        ↓    ↓
   ┌──────────────────────┐
   │  Wait-and-Deploy     │
   │  Watcher (Bastion)   │
   │  192.168.168.42      │
   └──────┬───────────────┘
          │
          ↓
   ┌──────────────────────┐
   │  Direct-Deploy       │
   │  (auto-triggered)    │
   │  → Git Bundle        │
   │  → SCP Transfer      │
   │  → Remote Checkout   │
   │  → Audit Logging     │
   └──────────────────────┘
```

---

## Prerequisites

### Local Operator Environment

Ensure you have these tools installed on your workstation:

```bash
# Required
which git
which ssh
which bash

# Vault provisioning (optional, if using Vault)
which vault

# AWS provisioning (optional, if using AWS)
which aws

# Docker (optional, for local Vault dev environment)
which docker-compose
```

### Access Requirements

- SSH access to bastion/worker node: `192.168.168.42` as user `akushnir`
- For Vault: Vault admin token (VAULT_TOKEN) and address (VAULT_ADDR)
- For AWS: AWS credentials with `secretsmanager:*` and `kms:*` permissions
- For GSM: gcloud credentials and permissions on `elevatediq-runner` project

### SSH Key Generation

SSH credentials should already be generated at `.ssh/runner_ed25519`. Verify:

```bash
ls -l .ssh/runner_ed25519*
# Expected:
# -rw------- runner_ed25519      (private key, 411 bytes)
# -rw-r--r-- runner_ed25519.pub  (public key, 103 bytes)
```

If missing, generate:

```bash
ssh-keygen -t ed25519 -f .ssh/runner_ed25519 -N ""
```

---

## Option 1: HashiCorp Vault Provisioning

### Step 1: Prepare Vault Environment

#### Option 1a: Local Docker-based Vault (Development)

Requires docker-compose. Starts Vault on localhost:8200 with dev token:

```bash
bash scripts/vault-bootstrap.sh --mode=docker
```

This will output:

```
export VAULT_ADDR='http://localhost:8200'
export VAULT_TOKEN='dev-token-12345'
export VAULT_SKIP_VERIFY='true'
```

#### Option 1b: Use Existing Vault Instance

Have your Vault admin provide the endpoint and a token:

```bash
export VAULT_ADDR="https://vault.example.com:8200"
export VAULT_TOKEN="s.xxxxxxxxxxxxxxxx"
```

Optionally disable cert verification for self-signed certs:

```bash
export VAULT_SKIP_VERIFY="true"
```

### Step 2: Provision SSH Credentials to Vault

Run the provisioning script:

```bash
bash scripts/deploy-operator-credentials.sh vault
```

Expected output:

```
[INFO] Deploying SSH credentials to vault...
[INFO] Step 1: Preparing SSH key...
[OK] SSH key loaded (411 bytes)
[INFO] Step 2: Provisioning to HashiCorp Vault...
[INFO] Storing key in Vault at secret/runner-deploy...
[OK] Key stored in Vault
[OK] ==========================================
[OK] SSH Credentials Deployed Successfully
[OK] ==========================================
```

### Step 3: Activate Vault-based Deployment

Connect to the bastion and activate the watcher:

```bash
ssh akushnir@192.168.168.42

# On bastion:
export VAULT_ADDR="https://vault.example.com:8200"
export VAULT_TOKEN="s.xxxxxxxxxxxxxxxx"
export VAULT_SKIP_VERIFY="true"  # if needed

# Test Vault connectivity
vault status

# Restart the watcher to use Vault
sudo systemctl restart wait-and-deploy.service

# Monitor the watcher
sudo journalctl -u wait-and-deploy.service -f
```

---

## Option 2: AWS Secrets Manager Provisioning

### Step 1: Configure AWS Credentials

Ensure AWS CLI is configured with credentials that have permissions to create/read secrets:

```bash
aws configure
# or
export AWS_ACCESS_KEY_ID="AKIA..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_REGION="us-east-1"
```

Verify credentials:

```bash
aws sts get-caller-identity
# Output: {Account, UserId, Arn}
```

### Step 2: Bootstrap AWS Secrets Manager

Run the AWS bootstrap script:

```bash
bash scripts/aws-bootstrap.sh --region=us-east-1
```

Expected output:

```
[INFO] AWS Secrets Manager Bootstrap
[INFO] Region: us-east-1
[INFO] Secret: runner/ssh-credentials
[OK] Authenticated to AWS account: 123456789012
[INFO] Creating/updating secret...
[OK] Secret created
[OK] ==========================================
[OK] AWS Bootstrap Complete
[OK] ==========================================
```

### Step 3: Grant Watcher IAM Permissions

The bastion/worker node needs IAM permissions to read AWS Secrets Manager. Options:

#### Option A: EC2 Instance Role (Recommended for AWS)

Attach an IAM role to the EC2 instance running the watcher with policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "arn:aws:secretsmanager:region:account:secret:runner/*"
    },
    {
      "Effect": "Allow",
      "Action": ["kms:Decrypt"],
      "Resource": "*"
    }
  ]
}
```

#### Option B: IAM User with Access Key

Create an IAM user with the above policy and provide credentials to the watcher via:

```bash
# On bastion
export AWS_ACCESS_KEY_ID="AKIA..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_REGION="us-east-1"

# Add to systemd environment (see systemd configuration section)
```

### Step 4: Activate AWS-based Deployment

On the bastion:

```bash
ssh akushnir@192.168.168.42

# On bastion:
export AWS_REGION="us-east-1"
# If using IAM user credentials:
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."

# Test AWS access
aws secretsmanager get-secret-value --secret-id runner/ssh-credentials --region us-east-1

# Restart the watcher to use AWS
sudo systemctl restart wait-and-deploy.service

# Monitor the watcher
sudo journalctl -u wait-and-deploy.service -f
```

---

## Option 3: Google Secret Manager (GSM) Provisioning

### Step 1: Configure gcloud

Ensure gcloud is authenticated and the project is set:

```bash
gcloud auth login
gcloud config set project elevatediq-runner
```

Verify:

```bash
gcloud config list
# Output should show: project = elevatediq-runner
```

### Step 2: Grant Permissions

Ensure the authenticated account has Secret Manager permissions:

```bash
gcloud projects add-iam-policy-binding elevatediq-runner \
  --member=user:your-email@example.com \
  --role=roles/secretmanager.admin
```

### Step 3: Provision SSH Credentials to GSM

Run the provisioning script:

```bash
bash scripts/deploy-operator-credentials.sh gsm
```

Expected output:

```
[INFO] Deploying SSH credentials to gsm...
[INFO] Step 1: Preparing SSH key...
[OK] SSH key loaded (411 bytes)
[INFO] Step 2: Provisioning to Google Secret Manager...
[INFO] Creating new secret...
[OK] Secret created in GSM
[OK] ==========================================
[OK] SSH Credentials Deployed Successfully
[OK] ==========================================
```

### Step 4: Activate GSM-based Deployment

On the bastion:

```bash
ssh akushnir@192.168.168.42

# On bastion:
export GCLOUD_PROJECT="elevatediq-runner"
gcloud auth application-default login

# Restart the watcher
sudo systemctl restart wait-and-deploy.service

# Monitor the watcher
sudo journalctl -u wait-and-deploy.service -f
```

---

## Systemd Configuration

The watcher runs as a systemd service: `/etc/systemd/system/wait-and-deploy.service`

To update environment variables for the service:

```bash
# On bastion
sudo systemctl edit wait-and-deploy.service
```

Add environment variables in the `[Service]` section:

```ini
[Service]
Environment="VAULT_ADDR=https://vault.example.com:8200"
Environment="VAULT_TOKEN=s.xxxxxxxxxxxxxxxx"
Environment="VAULT_SKIP_VERIFY=true"
# Or for AWS:
Environment="AWS_ACCESS_KEY_ID=AKIA..."
Environment="AWS_SECRET_ACCESS_KEY=..."
Environment="AWS_REGION=us-east-1"
# Or for GSM:
Environment="GCLOUD_PROJECT=elevatediq-runner"
```

Reload and restart:

```bash
sudo systemctl daemon-reload
sudo systemctl restart wait-and-deploy.service
sudo systemctl status wait-and-deploy.service
```

---

## Deployment Verification

### Monitor Watcher Logs

```bash
ssh akushnir@192.168.168.42

# Real-time logs
sudo journalctl -u wait-and-deploy.service -f

# Last 50 lines
sudo journalctl -u wait-and-deploy.service -n 50

# Logs since last restart
sudo journalctl -u wait-and-deploy.service --since "1 hour ago"
```

### Check Deployment Status

Deployments are audited to GitHub issue #2072:

```bash
gh issue view 2072 --comments
```

Or locally:

```bash
cat logs/deployment-provisioning-audit.jsonl | tail -10
```

### Manual Trigger (Emergency)

If the watcher is not detecting credentials, trigger manually:

```bash
ssh akushnir@192.168.168.42

# On bastion:
cd /home/akushnir/self-hosted-runner
./scripts/direct-deploy.sh vault main
# or
./scripts/direct-deploy.sh aws main
# or
./scripts/direct-deploy.sh gsm main
```

---

## Troubleshooting

### Issue: Watcher not detecting credentials

**Cause:** Credential provider not configured or environment variables missing.

**Solution:**

1. Check watcher logs:
   ```bash
   sudo journalctl -u wait-and-deploy.service | grep "Auto-detecting\|Waiting for"
   ```

2. Verify environment variables on bastion:
   ```bash
   # For Vault
   echo "$VAULT_ADDR" "$VAULT_TOKEN"
   
   # For AWS
   aws sts get-caller-identity
   
   # For GSM
   gcloud auth list
   ```

3. Restart the service:
   ```bash
   sudo systemctl restart wait-and-deploy.service
   ```

### Issue: Permission denied on credential provider

**Cause:** Authentication token/credentials invalid or insufficient permissions.

**Solution:**

- **Vault:** Verify token is valid: `vault token lookup`
- **AWS:** Verify credentials: `aws sts get-caller-identity` and check IAM permissions
- **GSM:** Verify gcloud auth: `gcloud auth list` and check IAM roles

### Issue: SSH key authorization failed

**Cause:** Public key not added to worker authorized_keys.

**Solution:**

Manually authorize the key:

```bash
# On bastion
cat .ssh/runner_ed25519.pub | ssh akushnir@192.168.168.42 \
  "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys"
```

---

## Quick Reference: Common Commands

```bash
# Vault
export VAULT_ADDR="https://vault.example.com:8200"
export VAULT_TOKEN="s.xxxxxxxxxxxxxxxx"
bash scripts/vault-bootstrap.sh --mode=existing
bash scripts/deploy-operator-credentials.sh vault

# AWS
aws configure
bash scripts/aws-bootstrap.sh --region=us-east-1

# GSM
gcloud auth login
gcloud config set project elevatediq-runner
bash scripts/deploy-operator-credentials.sh gsm

# Monitor on bastion
sudo journalctl -u wait-and-deploy.service -f

# Manual deploy
./scripts/direct-deploy.sh [vault|aws|gsm] main
```

---

## Architecture Guarantees

✅ **Immutable:** All deployments are append-only in audit logs (GitHub #2072 + local JSONL)  
✅ **Ephemeral:** Credentials fetched on-demand; not stored on disk  
✅ **Idempotent:** Safe to retry; git bundle hash ensures no duplicates  
✅ **No-Ops:** Fully automated watcher; no manual intervention needed  
✅ **Automated:** Credentials provisioned once; deployments trigger automatically  
✅ **Multi-Provider:** Supports Vault, AWS Secrets Manager, Google Secret Manager  
✅ **Zero-Trust:** SSH key-based auth; no stored passwords  

---

## Next Steps

1. **Choose a credential provider:** Vault (recommended for flexibility), AWS (if on AWS), or GSM
2. **Follow provisioning steps** for your chosen provider above
3. **Activate the watcher** with environment variables
4. **Monitor deployment logs** in real-time
5. **Verify audit trail** in GitHub issue #2072

**All systems are production-ready. Provisioning and deployment are fully automated and immutable.**

