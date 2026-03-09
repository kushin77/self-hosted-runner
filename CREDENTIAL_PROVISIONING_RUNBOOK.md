# 🔐 Credential Provisioning Runbook
**Status:** 🟡 **ACTIVE** | **Last Updated:** 2026-03-09 | **Maintainer:** ops/security

---

## 📋 Overview

This runbook covers provisioning deployment credentials for the **immutable, ephemeral, idempotent, hands-off deployment** system using **Vault**, **AWS Secrets Manager**, and **Google Secret Manager (GSM)**.

**Key Principles:**
- ✅ **Immutable:** All credentials stored in external secret managers (no `.git` commits).
- ✅ **Ephemeral:** Credentials are fetched at runtime and not persisted on disk.
- ✅ **Idempotent:** Deploy scripts can be run repeatedly without side effects.
- ✅ **No-ops:** Watcher automation handles deployment; operators only provision secrets.
- ✅ **Fully Automated:** Once provisioned, all deploys to **192.168.168.42** are hands-off.

---

## 🎯 Provisioning Checklist

| Provider | Status | Issue | Action |
|----------|--------|-------|--------|
| **Vault (KV v2)** | ✅ Active | #2101 | [Harden & replace dev token](#vault-production-hardening) |
| **AWS Secrets Manager** | ⏳ Pending | #2100 | [Create secret & IAM role](#aws-provisioning) |
| **Google Secrets Manager** | ⏳ Pending | #2103 | [Grant IAM permissions](#gsm-provisioning) |
| **CI/PR Workflows** | ❌ Enabled | #2102 | [Disable CI/PR policy](#disable-cipr-workflows) |
| **Deployment Policy** | ⏳ Draft | #2104 | [Enforce immutable/ephemeral/idempotent](#deployment-policy-enforcement) |

---

## 🏠 Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Operator Workstation                                        │
│ - Provision SSH private key to external secret manager      │
│ - Trigger manual deploy or update watcher config           │
└──────────────────────┬──────────────────────────────────────┘
                       │
         ┌─────────────┴──────────────────┐
         │                                │
    ┌────▼─────┐                  ┌──────▼────┐
    │   Vault  │                  │ AWS / GSM │
    │ (KV v2)  │                  │ (alt)     │
    └────┬─────┘                  └──────┬────┘
         │                                │
         └─────────────┬──────────────────┘
                       │
         ┌─────────────▼──────────────────┐
         │ Bastion (192.168.168.31)       │
         │ - Watcher service              │
         │ - Auto-detect provider         │
         │ - Fetch & store credentials    │
         └──────────────┬──────────────────┘
                        │
    ┌───────────────────▼───────────────────┐
    │ Worker (192.168.168.42)               │
    │ - Receive immutable git bundle        │
    │ - Unpack, checkout, deploy           │
    │ - Append audit log (local + GitHub)   │
    └───────────────────────────────────────┘
```

---

## 🔧 Vault Provisioning (✅ Currently Active)

### 1️⃣ Vault Bootstrap (if needed)

```bash
# Start Vault dev server (for testing only)
vault server -dev -dev-root-token-id=dev-token-$(date +%s) -dev-listen-address=127.0.0.1:8200

# In another terminal, export credentials
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='dev-token-...'  # From server output

# Enable KV v2 (if not already enabled)
vault secrets enable -version=2 kv
```

### 2️⃣ Provision SSH Key to Vault

```bash
# Store SSH private key
bash scripts/deploy-operator-credentials.sh vault

# Verify
vault kv get -format=json secret/runner-deploy | jq '.data.data'
```

**Output:**
```json
{
  "ssh_key": "-----BEGIN OPENSSH PRIVATE KEY-----\n...",
  "ssh_user": "akushnir"
}
```

### 3️⃣ Configure Watcher on Bastion (192.168.168.31)

```bash
# SSH to bastion
ssh akushnir@192.168.168.31

# Create systemd drop-in environment file
sudo tee /etc/systemd/system/wait-and-deploy.service.d/override.conf <<EOF
[Service]
Environment="VAULT_ADDR=http://127.0.0.1:8200"
Environment="VAULT_TOKEN=dev-token-<your-token>"
Environment="CRED_SOURCE=vault"
ExecStart=
ExecStart=/usr/local/bin/wait-and-deploy.sh
EOF

# Reload and restart
sudo systemctl daemon-reload
sudo systemctl restart wait-and-deploy.service

# Verify
sudo journalctl -u wait-and-deploy.service -f
```

**Expected Logs:**
```
wait-and-deploy[PID]: [INFO] Watcher polling every 30s
wait-and-deploy[PID]: [INFO] Detected provider: vault
wait-and-deploy[PID]: [OK] Credentials verified: secret/runner-deploy found
```

---

## ☁️ AWS Secrets Manager Provisioning (⏳ TODO - Issue #2100)

### Prerequisites
- AWS CLI configured with credentials
- IAM permissions to `secretsmanager:*` and `kms:*`

### 1️⃣ Create KMS Key (if needed)

```bash
# Create a customer-managed KMS key for secrets encryption
aws kms create-key \
  --description "Runner deployment secrets encryption" \
  --region us-east-1 \
  --tags TagKey=Environment,TagValue=production TagKey=Service,TagValue=runner

# Get the key ID
KMS_KEY_ID=$(aws kms list-keys --region us-east-1 | jq -r '.Keys[0].KeyId')

# Create an alias
aws kms create-alias \
  --alias-name alias/runner-deploy-key \
  --target-key-id $KMS_KEY_ID \
  --region us-east-1

echo "KMS_KEY_ID=$KMS_KEY_ID"
```

### 2️⃣ Store SSH Private Key in Secrets Manager

```bash
# Read the SSH private key
SSH_PRIVATE_KEY=$(cat ~/.ssh/runner_ed25519)

# Store in AWS Secrets Manager
aws secretsmanager create-secret \
  --name "runner/ssh-credentials" \
  --description "SSH private key for runner deployment" \
  --kms-key-id alias/runner-deploy-key \
  --secret-string "{\"ssh_key\":\"$SSH_PRIVATE_KEY\",\"ssh_user\":\"akushnir\"}" \
  --region us-east-1

# Verify
aws secretsmanager get-secret-value \
  --secret-id "runner/ssh-credentials" \
  --region us-east-1 | jq '.SecretString | fromjson'
```

### 3️⃣ Create IAM Role for Watcher Automation

```bash
# Create IAM policy for watcher
aws iam create-policy \
  --policy-name runner-watcher-policy \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "secretsmanager:GetSecretValue"
        ],
        "Resource": "arn:aws:secretsmanager:us-east-1:*:secret:runner/*"
      },
      {
        "Effect": "Allow",
        "Action": [
          "kms:Decrypt"
        ],
        "Resource": "'$KMS_KEY_ID'"
      }
    ]
  }' \
  --region us-east-1

# Create IAM user for watcher
aws iam create-user --user-name runner-watcher
TOKEN=$(aws iam create-access-key --user-name runner-watcher --query 'AccessKey.[AccessKeyId,SecretAccessKey]' --output text)
ACCESS_KEY=$(echo "$TOKEN" | awk '{print $1}')
SECRET_KEY=$(echo "$TOKEN" | awk '{print $2}')

# Attach policy to user
aws iam attach-user-policy \
  --user-name runner-watcher \
  --policy-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/runner-watcher-policy

# Store credentials in Vault or environment
echo "export AWS_ACCESS_KEY_ID='$ACCESS_KEY'"
echo "export AWS_SECRET_ACCESS_KEY='$SECRET_KEY'"
echo "export AWS_REGION='us-east-1'"
```

### 4️⃣ Configure Watcher for AWS

```bash
# SSH to bastion
ssh akushnir@192.168.168.31

# Update systemd drop-in to use AWS
sudo tee /etc/systemd/system/wait-and-deploy.service.d/override.conf <<EOF
[Service]
Environment="AWS_ACCESS_KEY_ID=<your-access-key>"
Environment="AWS_SECRET_ACCESS_KEY=<your-secret-key>"
Environment="AWS_REGION=us-east-1"
Environment="CRED_SOURCE=aws"
ExecStart=
ExecStart=/usr/local/bin/wait-and-deploy.sh
EOF

# Reload and restart
sudo systemctl daemon-reload
sudo systemctl restart wait-and-deploy.service

# Verify
sudo journalctl -u wait-and-deploy.service -f
```

---

## 🌐 Google Secret Manager Provisioning (⏳ TODO - Issue #2103)

### Prerequisites
- `gcloud` CLI configured
- IAM role `roles/secretmanager.admin` on the GCP project

### 1️⃣ Enable GSM API

```bash
gcloud services enable secretmanager.googleapis.com --project=elevatediq-runner
```

### 2️⃣ Store SSH Private Key

```bash
# Read SSH key and create secret
SSH_PRIVATE_KEY=$(cat ~/.ssh/runner_ed25519)

echo "{\"ssh_key\":\"$SSH_PRIVATE_KEY\",\"ssh_user\":\"akushnir\"}" | \
  gcloud secrets create runner-deploy \
  --data-file=- \
  --project=elevatediq-runner

# Verify
gcloud secrets versions access latest --secret=runner-deploy --project=elevatediq-runner | jq '.ssh_user'
```

### 3️⃣ Grant IAM Permissions

```bash
# Get the service account that will access GSM
SERVICE_ACCOUNT="runner-watcher-sa@elevatediq-runner.iam.gserviceaccount.com"

# Grant secretAccessor role
gcloud projects add-iam-policy-binding elevatediq-runner \
  --member=serviceAccount:$SERVICE_ACCOUNT \
  --role=roles/secretmanager.secretAccessor

# Verify
gcloud projects get-iam-policy elevatediq-runner \
  --flatten="bindings[].members" \
  --filter="bindings.role:roles/secretmanager.secretAccessor" \
  --format="table(bindings.members)"
```

### 4️⃣ Configure Watcher for GSM

```bash
# SSH to bastion
ssh akushnir@192.168.168.31

# Authenticate with gcloud
gcloud auth application-default login

# Update systemd drop-in
sudo tee /etc/systemd/system/wait-and-deploy.service.d/override.conf <<EOF
[Service]
Environment="CRED_SOURCE=gsm"
Environment="GSM_PROJECT=elevatediq-runner"
ExecStart=
ExecStart=/usr/local/bin/wait-and-deploy.sh
EOF

# Reload and restart
sudo systemctl daemon-reload
sudo systemctl restart wait-and-deploy.service

# Verify
sudo journalctl -u wait-and-deploy.service -f
```

---

## 🔒 Vault Production Hardening (⏳ TODO - Issue #2101)

**Current State:** Dev token used (not production-ready).

### 1️⃣ Replace Dev Token with AppRole

```bash
# Enable AppRole auth on production Vault
vault auth enable approle

# Create approle for runner automation
vault write auth/approle/role/runner-automation \
  token_num_uses=0 \
  token_ttl=1h \
  token_max_ttl=4h

# Get Role ID
ROLE_ID=$(vault read auth/approle/role/runner-automation/role-id --format=json | jq -r '.data.role_id')

# Generate Secret ID
SECRET_ID=$(vault write -f auth/approle/role/runner-automation/secret-id --format=json | jq -r '.data.secret_id')

echo "ROLE_ID=$ROLE_ID"
echo "SECRET_ID=$SECRET_ID"
```

### 2️⃣ Configure Vault Agent on Bastion

```bash
# SSH to bastion
ssh akushnir@192.168.168.31

# Create Vault Agent config
sudo tee /etc/vault-agent.hcl <<EOF
pid_file = "/tmp/pidfile"

vault {
  address = "https://vault.production.example.com:8200"
}

auto_auth {
  method "approle" {
    mount_path = "auth/approle"
    config = {
      role_id_file_path = "/var/vault/role-id"
      secret_id_file_path = "/var/vault/secret-id"
      remove_secret_id_file_after_reading = false
    }
  }

  sink "file" {
    config = {
      path = "/var/run/vault/.vault-token"
      owner = "root"
      group = "root"
      perms = "0600"
    }
  }
}
EOF

# Create Vault Agent systemd service
sudo tee /etc/systemd/system/vault-agent.service <<EOF
[Unit]
Description=Vault Agent
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=/var/vault/role-id

[Service]
Type=notify
ExecStart=/usr/local/bin/vault agent -config=/etc/vault-agent.hcl
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Store AppRole credentials securely
sudo mkdir -p /var/vault
echo "$ROLE_ID" | sudo tee /var/vault/role-id
echo "$SECRET_ID" | sudo tee /var/vault/secret-id
sudo chmod 600 /var/vault/{role-id,secret-id}

# Start Vault Agent
sudo systemctl daemon-reload
sudo systemctl enable --now vault-agent.service
```

### 3️⃣ Update Watcher to Use Vault Agent

```bash
# Update systemd drop-in to use token from Vault Agent
sudo tee /etc/systemd/system/wait-and-deploy.service.d/override.conf <<EOF
[Service]
Environment="VAULT_ADDR=https://vault.production.example.com:8200"
Environment="VAULT_TOKEN_FILE=/var/run/vault/.vault-token"
Environment="CRED_SOURCE=vault"
ExecStart=
ExecStart=/usr/local/bin/wait-and-deploy.sh
EOF

# Update wait-and-deploy.sh to read token from file
# (This should be added by the ops team in the script update)

# Restart watcher
sudo systemctl daemon-reload
sudo systemctl restart wait-and-deploy.service
```

---

## ❌ Disable CI/PR Workflows (⏳ TODO - Issue #2102)

**Current State:** CI workflows trigger on PR/push; some trigger production deploys.

### 1️⃣ Archive Workflow Files

```bash
# Move production-deploy workflows to archive
mkdir -p .github/workflows/archive
git mv .github/workflows/production-deploy.yml .github/workflows/archive/
git mv .github/workflows/release-on-main.yml .github/workflows/archive/

# Disable PR-based deployments
git checkout .github/workflows/pr-checks.yml  # Keep only static checks
git restore --worktree .github/workflows/pr-checks.yml  # Remove deploy steps

git add .github/workflows/
git commit -m "chore(ci): disable PR-based production deploys; use direct-deploy only"
git push origin main
```

### 2️⃣ Update Branch Protection

```bash
# Use GitHub CLI to update branch protections
gh api repos/{owner}/{repo}/branches/main/protection \
  -f required_status_checks=null \
  -f required_pull_request_reviews='{"required_approving_review_count":1}' \
  -f allow_deletions=false \
  -f allow_force_pushes=false
```

### 3️⃣ Update CODEOWNERS

```bash
# Ensure only ops can approve deployments
echo "# Deployments require ops approval" >> CODEOWNERS
echo "scripts/deploy*.sh @kushin77" >> CODEOWNERS
echo "scripts/direct-deploy.sh @kushin77" >> CODEOWNERS

git add CODEOWNERS
git commit -m "chore: restrict deploy scripts to ops team"
git push origin main
```

---

## 📋 Deployment Policy Enforcement (⏳ TODO - Issue #2104)

### 1️⃣ Document Immutable Bundle Policy

Create `GIT_GOVERNANCE_STANDARDS.md` section:

```markdown
## Deployment Policy

### ✅ ALLOWED
- Operator runs `./scripts/deploy.sh` → creates immutable bundle → SCP to worker → idempotent checkout
- All credentials fetched from external manager at deploy time
- Audit stored in append-only JSONL + GitHub comments
- No direct commits to production in git repo

### ❌ NOT ALLOWED
- Committing SSH keys, API tokens, or credentials to git
- Merging feature branches to main without ops approval
- Triggering deploys via CI/GitHub Actions (except audit/logging)
- Storing credentials in environment variables in CI (they're moved to external managers)
- Direct SSH to worker for manual edits (use bundle + deploy script)
```

### 2️⃣ Add PR Template

Create `.github/pull_request_template.md`:

```markdown
# Deployment Checklist

- [ ] No credentials committed to git
- [ ] Bundle is immutable (git commit hash included)
- [ ] Deploy script is idempotent (safe to run repeatedly)
- [ ] Audit trail will be appended (JSONL + GitHub comment)
- [ ] Secrets fetched from Vault/AWS/GSM (not hardcoded)

> **Note:** This PR does NOT trigger production deploy. Use `./scripts/deploy.sh` after merge.
```

### 3️⃣ Pre-commit Hooks

Create `.git/hooks/pre-commit`:

```bash
#!/bin/bash
# Prevent committing credentials

PATTERN="(-----BEGIN|ssh-rsa|PRIVATE|password|api_key|secret)"

if git diff --cached | grep -iE "$PATTERN"; then
  echo "❌ Error: Detected potential credentials in staged files"
  echo "   Please remove and add to external secret manager instead"
  exit 1
fi
```

---

## 🚀 End-to-End Test

Once all providers are configured:

```bash
# 1. Manually trigger a deploy
bash scripts/deploy.sh main

# 2. Verify on worker
ssh akushnir@192.168.168.42
cat /tmp/deployment-audit.jsonl | jq 'select(.status=="success")'

# 3. Verify audit on GitHub
gh issue view 2072 --json comments | jq '.comments[-1]'

# 4. Verify watcher auto-detection
ssh akushnir@192.168.168.31
sudo journalctl -u wait-and-deploy.service --since "1 hour ago" | grep "Detected provider"
```

---

## 📞 Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `Vault unreachable (connection refused)` | VAULT_ADDR env var not set | Set VAULT_ADDR in systemd drop-in or export in shell |
| `secret not found in vault` | SSH key not provisioned | Run `bash scripts/deploy-operator-credentials.sh vault` |
| `gcloud: permission denied on project` | Service account lacks IAM role | Run `gcloud projects add-iam-policy-binding` with correct role |
| `No such file or directory: direct-deploy.sh` | Watcher script path misconfigured | Ensure `cd $REPO_ROOT` before invoking `./scripts/direct-deploy.sh` |
| `AWS: Unable to locate credentials` | AWS CLI not authenticated | Run `aws configure` or set `AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY` |

---

## 📚 Related Issues & Docs

- **Issue #2100:** [Provision AWS Secrets Manager](https://github.com/kushin77/self-hosted-runner/issues/2100)
- **Issue #2101:** [Vault Production Hardening](https://github.com/kushin77/self-hosted-runner/issues/2101)
- **Issue #2102:** [Disable CI/PR Workflows](https://github.com/kushin77/self-hosted-runner/issues/2102)
- **Issue #2103:** [GSM Permissions](https://github.com/kushin77/self-hosted-runner/issues/2103)
- **Issue #2104:** [Policy Enforcement](https://github.com/kushin77/self-hosted-runner/issues/2104)
- **Issue #2072:** [Deployment Audit Trail](https://github.com/kushin77/self-hosted-runner/issues/2072)
- **Docs:** `DEPLOYMENT_VAULT_AGENT_STATUS_FINAL.md`, `DEPLOYMENT_QUICK_START.md`
- **Scripts:** `scripts/deploy-operator-credentials.sh`, `scripts/wait-and-deploy.sh`, `scripts/manual-deploy-local-key.sh`

---

## ✅ Completion Checklist

**For full go-live of immutable/ephemeral/idempotent deployment system, complete in this order:**

### Phase 1: Vault Production Hardening (Issue #2101)
- [ ] Replace dev token with AppRole
- [ ] Deploy Vault Agent on bastion (systemd service)
- [ ] Update watcher to use agent token file
- [ ] Test successful Vault login and deploy

### Phase 2: Choose Second Credential Provider (Issue #2100 OR #2103)

**Option A: AWS Secrets Manager (#2100) — Recommended if running on EC2**
- [ ] Create KMS key for encryption
- [ ] Provision `runner/ssh-credentials` secret
- [ ] Create IAM role + policy for watcher
- [ ] Configure watcher to use AWS provider
- [ ] Test successful AWS login and deploy

**Option B: GSM (#2103) — Recommended if running on GCP**
- [ ] Grant service account `roles/secretmanager.secretAccessor`
- [ ] Provision `runner-deploy` secret
- [ ] Test `gcloud` access and credential fetch
- [ ] Configure watcher to use GSM provider
- [ ] Test successful GSM login and deploy

### Phase 3: Disable CI/PR Workflows (Issue #2102)
- [ ] Verify workflows are archived in `.github/workflows/archive/`
- [ ] Verify no production triggers on PR/push
- [ ] Test manual workflow_dispatch only
- [ ] Document policy in `CONTRIBUTING.md`

### Phase 4: Enforce Deployment Policy (Issue #2104)
- [ ] Add pre-commit hook to detect hardcoded secrets
- [ ] Add PR template reminding operators of no-secrets rule
- [ ] Update `GIT_GOVERNANCE_STANDARDS.md` with enforcement rules
- [ ] Run audit on recent commits to verify compliance

### Phase 5: Validate End-to-End
- [ ] Run `bash scripts/deploy.sh main`
- [ ] Verify worker receives immutable bundle
- [ ] Verify audit appended to GitHub issue #2072
- [ ] Verify watcher logs show auto-detection of active provider
- [ ] Verify zero manual ops required (fully hands-off)

---

## 🔄 Version History

| Date | Author | Change |
|------|--------|--------|
| 2026-03-09 | ops | ✅ Completed: Created all 6 provisioning issues + added completion checklist + linked all governance tasks |
| 2026-03-09 | ops | ✅ Vault dev provisioning active; watcher auto-detect functional; manual deploys working |
| 2026-03-09 | ops | Created runbook with Vault/AWS/GSM provisioning steps |

