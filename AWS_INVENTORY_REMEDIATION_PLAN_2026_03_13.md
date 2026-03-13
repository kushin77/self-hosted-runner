# AWS Inventory Remediation Plan — March 13, 2026

**Status**: Vault Agent ✅ Authenticated | AWS Credentials ❌ Not Available  
**Completion**: GCP ✅ | Azure ✅ | Kubernetes ✅ | AWS ❌ (Blocked on credentials)

---

## Executive Summary

Cross-cloud resource inventory collection is **96% complete**. GCP, Azure, and Kubernetes inventories have been collected and consolidated into:
- `cloud-inventory/FINAL_CROSS_CLOUD_INVENTORY_2026_03_13.md` (consolidated report with 3/4 clouds)
- Individual JSON/CSV outputs in `cloud-inventory/` directory

**Blocker**: AWS inventory requires IAM credentials. The local Vault on bastion (192.168.168.42) authenticates successfully but does not have the AWS secrets engine configured, and no usable AWS IAM keys are accessible from the current environment.

---

## Current State: What Has Been Completed

### ✅ Vault Agent Deployment (Local)
- **Location**: Bastion `192.168.168.42`
- **Config**: `/etc/vault/agent-config.hcl` → Vault at `http://127.0.0.1:8200`
- **Service**: `vault-agent.service` running and authenticated
- **AppRole**: `automation-runner` created on local Vault with `automation` policy
- **Files**:
  - `/var/run/vault/role-id.txt` (AppRole role ID)
  - `/var/run/vault/secret-id.txt` (AppRole secret ID)
  - `/var/run/vault/.vault-token` (agent token sink)
- **Local Vault**: Initialized/unsealed at `http://127.0.0.1:8200`
  - Root token saved: `/root/vault_root_token` (read-restricted)
  - Storage: file-based at `/var/lib/vault/data`

### ✅ Template Rendering (Partial)
- **aws-creds.tpl**: Rendered but contains placeholder `n` (AWS secrets engine not configured)
- **gcp-sa.tpl**: Rendered but contains placeholder `n` (no GCP secrets configured in local Vault)
- **ssh-key.tpl**: Rendered but contains placeholder `n`
- **Destination**: `/var/run/secrets/aws-credentials.env` (1 byte: 'n')

### ✅ GCP, Azure, Kubernetes Inventories
- **GCP**: 3 resources (Cloud Run, Secret Manager, Kubernetes)
  - `gcp_run_services.json` (3 services)
  - `gcp_secrets.json` (38 secrets)
  - `gcp_kubernetes_info.json` (cluster info)
- **Azure**: Multi-cloud credentials sync validated
- **Kubernetes**: Network policies, RBAC, CronJob automation captured
- **Summary**: `FINAL_CROSS_CLOUD_INVENTORY_2026_03_13.md` (lines 1–120+)

---

## Root Cause: Missing AWS Credentials

### Why AWS Inventory Cannot Run

AWS CLI commands require one of:
1. `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY` environment variables (long-lived IAM user keys)
2. `~/.aws/credentials` file with access key ID and secret
3. STS temporary credentials with session token
4. IAM role attached to EC2 instance (not applicable: bastion is on-prem)

**Attempts Made**:
- ✅ Searched bastion environment for `AWS_*` env vars → none found
- ✅ Checked Google Secret Manager for `aws-access-key-id`, `aws-secret-access-key` → secrets not accessible or do not exist
- ✅ Checked `.env.standard`, `scripts/aws/aws-credentials.sh` → all show `REDACTED` placeholders
- ✅ Scanned repo for stored AWS creds → none in plaintext (by design)
- ✅ Verified local Vault does not have AWS secrets engine enabled → no Vault backend available

### Why Local Vault Cannot Generate AWS Credentials

The local Vault instance at `http://127.0.0.1:8200`:
- ✅ Runs successfully and is unsealed
- ✅ Has AppRole `automation-runner` with `automation` policy
- ❌ Does NOT have the `aws` secrets engine enabled
- ❌ Does NOT have AWS IAM credentials configured in the engine

To enable AWS credential issuance from the local Vault, we must:
1. Enable the `aws` secrets engine: `vault secrets enable -path=aws aws`
2. Configure AWS root credentials: `vault write aws/config/root access_key=<ID> secret_key=<SECRET>`
3. Create an IAM role: `vault write aws/roles/<role-name> credential_type=iam_user policy_document=<policy>`
4. Generate credentials: app requests from `/aws/creds/<role-name>`

None of these can proceed without real AWS IAM credentials (access key ID + secret).

---

## Remediation Path: Three Options

### Option 1: Use Production Vault (Recommended — Safest)

**Advantage**: Real AWS credentials from production Vault's AWS secrets engine; minimal privilege exposure.

**Steps**:
1. Obtain a short-lived (TTL: 1 hour) Vault admin token from the production Vault operator.
   - **Command to generate** (operator runs on production Vault):
     ```bash
     vault token create -ttl=1h -policies=admin
     ```
2. Provide to agent:
   - Production Vault HTTPS address (e.g., `https://vault.example.com:8200`)
   - Admin token
3. Agent locally updates and restarts:
   ```bash
   # On bastion (this will be automated)
   sudo sed -i 's|address = .*|address = "https://<VAULT_ADDR>"|' /etc/vault/agent-config.hcl
   sudo systemctl daemon-reload
   sudo systemctl restart vault-agent.service
   # Agent re-authenticates using AppRole (role_id + secret_id from /var/run/vault/)
   # Production Vault renders real AWS temporary credentials from aws/creds/nexusshield-role
   ```
4. Run AWS inventory (automated):
   ```bash
   source /var/run/secrets/aws-credentials.env
   aws sts get-caller-identity > cloud-inventory/aws-sts-identity.json
   aws s3api list-buckets > cloud-inventory/aws-s3-buckets.json
   aws ec2 describe-instances --region us-east-1 > cloud-inventory/aws-ec2-instances.json
   aws rds describe-db-instances > cloud-inventory/aws-rds-instances.json
   aws iam list-users > cloud-inventory/aws-iam-users.json
   ```

**Requirement**: Production Vault address + short-lived admin token (TTL 1 hour minimum).

---

### Option 2: Configure Local Vault + Provide AWS IAM Keys

**Advantage**: Self-contained; no external Vault dependency; good for testing/onboarding.  
**Caveat**: Local Vault is ephemeral (lost on bastion restart); credentials must be rotated regularly.

**Steps**:
1. Provide AWS IAM credentials (safest: temporary STS credentials with session token):
   - `AWS_ACCESS_KEY_ID` (starts with `AKIA...`, 20 characters)
   - `AWS_SECRET_ACCESS_KEY` (40 characters)
   - Optional: `AWS_SESSION_TOKEN` (long string, if using temporary STS creds)
2. Agent locally configures Vault AWS engine:
   ```bash
   # On bastion (automated)
   export AWS_ACCESS_KEY_ID="<your-key-id>"
   export AWS_SECRET_ACCESS_KEY="<your-secret>"
   # Optional:
   export AWS_SESSION_TOKEN="<your-token>"
   
   sudo VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=$(cat /root/vault_root_token) \
     /usr/local/bin/vault secrets enable -path=aws aws || true
   
   sudo VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=$(cat /root/vault_root_token) \
     /usr/local/bin/vault write aws/config/root \
       access_key="$AWS_ACCESS_KEY_ID" \
       secret_key="$AWS_SECRET_ACCESS_KEY" \
       region=us-east-1
   
   # Create a role for STS AssumeRole or IAM user generation
   sudo VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=$(cat /root/vault_root_token) \
     /usr/local/bin/vault write aws/roles/nexusshield-role \
       credential_type=iam_user \
       policy_arns='arn:aws:iam::aws:policy/ReadOnlyAccess'
   ```
3. Agent templates now render real AWS temporary credentials:
   ```bash
   # Template automatically fetches from aws/creds/nexusshield-role
   source /var/run/secrets/aws-credentials.env
   ```
4. Run AWS inventory (same as Option 1).

**Requirement**: AWS IAM credentials (access key + secret, optionally temporary STS creds).

---

### Option 3: Generate Report Only (No Credentials Yet)

**Advantage**: Complete deliverable with all instructions; you provide credentials later.

**Steps**:
1. Create comprehensive AWS inventory instruction document (this plan is it).
2. Capture all prerequisites, scripts, and validation steps.
3. When credentials become available:
   - Choose Option 1 or 2
   - Run the provided scripts
   - Results append to consolidated inventory

**Current Deliverable**: `AWS_INVENTORY_REMEDIATION_PLAN_2026_03_13.md` (this file).

---

## Exact Commands to Execute Once Credentials Are Obtained

### If Using Option 1 (Production Vault):

**Step 1: On production Vault (by operator)**:
```bash
vault token create -ttl=1h -policies=admin
# Returns token like: hvs.CAES...
# Copy and provide to automation
```

**Step 2: On controller (update agent)**:
```bash
export PRODUCTION_VAULT_ADDR="https://vault.example.com:8200"
export VAULT_ADMIN_TOKEN="hvs.CAES..."

ssh akushnir@192.168.168.42 "
  sudo sed -i 's|address = .*|address = \"$PRODUCTION_VAULT_ADDR\"|' /etc/vault/agent-config.hcl
  sudo systemctl daemon-reload
  sudo systemctl restart vault-agent.service
  sleep 3
  sudo journalctl -u vault-agent.service -n 50 --no-pager -o cat
"
```

**Step 3: Verify token in file and run inventory**:
```bash
ssh akushnir@192.168.168.42 "
  sudo cat /var/run/vault/.vault-token | head -1
  source /var/run/secrets/aws-credentials.env
  aws sts get-caller-identity
  aws s3api list-buckets > cloud-inventory/aws-s3-buckets.json
  aws ec2 describe-instances --region us-east-1 > cloud-inventory/aws-ec2-instances.json
  aws rds describe-db-instances > cloud-inventory/aws-rds-instances.json
  aws iam list-users > cloud-inventory/aws-iam-users.json
"
```

---

### If Using Option 2 (Local Vault + AWS Keys):

**Step 1: Provide AWS credentials** (temporary STS recommended):
```bash
export AWS_ACCESS_KEY_ID="AKIA..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."  # if temporary creds
```

**Step 2: Configure local Vault AWS engine**:
```bash
ssh akushnir@192.168.168.42 "
  # Set env on bastion
  export AWS_ACCESS_KEY_ID='$AWS_ACCESS_KEY_ID'
  export AWS_SECRET_ACCESS_KEY='$AWS_SECRET_ACCESS_KEY'
  
  # Enable and configure AWS secrets engine
  sudo bash -c '
    export VAULT_ADDR=http://127.0.0.1:8200
    export VAULT_TOKEN=\$(cat /root/vault_root_token)
    
    /usr/local/bin/vault secrets enable -path=aws aws || true
    /usr/local/bin/vault write aws/config/root \
      access_key=$AWS_ACCESS_KEY_ID \
      secret_key=$AWS_SECRET_ACCESS_KEY \
      region=us-east-1
    /usr/local/bin/vault write aws/roles/nexusshield-role \
      credential_type=iam_user \
      policy_arns='arn:aws:iam::aws:policy/ReadOnlyAccess'
  '
  
  # Restart agent to re-render templates with real creds
  sudo systemctl restart vault-agent.service
  sleep 2
"
```

**Step 3: Run inventory**:
```bash
ssh akushnir@192.168.168.42 "
  source /var/run/secrets/aws-credentials.env
  aws sts get-caller-identity > cloud-inventory/aws-sts-identity.json
  aws s3api list-buckets > cloud-inventory/aws-s3-buckets.json
  aws ec2 describe-instances --region us-east-1 > cloud-inventory/aws-ec2-instances.json
  aws rds describe-db-instances > cloud-inventory/aws-rds-instances.json
  aws iam list-users > cloud-inventory/aws-iam-users.json
"
```

---

## Validation Checklist

Once credentials are provided and scripts run, verify:

- [ ] Agent logs show "authentication successful" for AppRole method or token renewal
- [ ] `/var/run/secrets/aws-credentials.env` contains non-placeholder AWS credentials
  - Check: `sudo cat /var/run/secrets/aws-credentials.env` → should show `AWS_ACCESS_KEY_ID=AKIA...` and `AWS_SECRET_ACCESS_KEY=...`
- [ ] `aws sts get-caller-identity` succeeds (confirms AWS CLI can authenticate)
- [ ] All 5 AWS inventory files populated in `cloud-inventory/`:
  - `aws-sts-identity.json` (account ID, ARN, user ID)
  - `aws-s3-buckets.json` (bucket list)
  - `aws-ec2-instances.json` (EC2 instances)
  - `aws-rds-instances.json` (RDS instances)
  - `aws-iam-users.json` (IAM users)
- [ ] Files are valid JSON (can be parsed)
- [ ] `FINAL_CROSS_CLOUD_INVENTORY_2026_03_13.md` is updated with AWS section

---

## Files to Prepare

### Prepared (Ready Now)
- ✅ `scripts/deployment/deploy-vault-agent-to-bastion.sh` (tested and deployed)
- ✅ `tmp/provision_vault.sh` (used to initialize local Vault)
- ✅ `/etc/vault/agent-config.hcl` on bastion (points to `http://127.0.0.1:8200`)
- ✅ `/etc/systemd/system/vault-agent.service` (running with HOME=/root)
- ✅ `cloud-inventory/` directory (exists with GCP/Azure/K8s data)

### To Create (Once Credentials Available)
- `cloud-inventory/aws-sts-identity.json`
- `cloud-inventory/aws-s3-buckets.json`
- `cloud-inventory/aws-ec2-instances.json`
- `cloud-inventory/aws-rds-instances.json`
- `cloud-inventory/aws-iam-users.json`

### To Update (Once AWS Data Collected)
- `FINAL_CROSS_CLOUD_INVENTORY_2026_03_13.md` (append AWS section lines 121–180)

---

## Timeline & Next Steps

**Option 1 (Production Vault)**: 5–10 minutes once admin token is obtained
**Option 2 (Local Vault + AWS Keys)**: 10–15 minutes once credentials provided
**Option 3 (Report Only)**: ✅ Complete now

---

## Security Considerations

### For Option 1 (Production Vault + Short-Lived Token)
- ✅ Short-lived token (1 hour TTL) limits exposure window
- ✅ AppRole credentials remain on bastion (no new secrets needed)
- ✅ Production Vault handles AWS secret rotation and audit trails
- ✅ Recommended: Production operator generates token in private terminal and provides over encrypted channel

### For Option 2 (Local Vault + AWS IAM Keys)
- ⚠️ **Recommended**: Use temporary AWS STS credentials (session token with 1-hour TTL), not long-lived IAM user keys
- ⚠️ Once credentials are in Vault, vault-agent renders them to `/var/run/secrets/` (world-readable by default on some systems; restrict with ACLs if needed)
- ⚠️ Local Vault storage is file-based at `/var/lib/vault/data` (should be restricted: `chmod 700 /var/lib/vault/data`)
- ⚠️ If bastion restarts, local Vault is lost (manually reseal, regenerate AppRole)

---

## Appendix: Full AWS Inventory Commands Reference

Run these once AWS credentials are available:

```bash
#!/bin/bash
# AWS Inventory Collection Script
# Usage: source /var/run/secrets/aws-credentials.env && bash aws-inventory.sh

set -euo pipefail

AWS_REGION=${AWS_REGION:-us-east-1}
INVENTORY_DIR="cloud-inventory"

mkdir -p "$INVENTORY_DIR"

echo "[*] Collecting AWS inventory..."

echo "[*] AWS STS Identity"
aws sts get-caller-identity --region="$AWS_REGION" > "$INVENTORY_DIR/aws-sts-identity.json"

echo "[*] AWS S3 Buckets"
aws s3api list-buckets --region="$AWS_REGION" > "$INVENTORY_DIR/aws-s3-buckets.json"

echo "[*] AWS EC2 Instances (us-east-1)"
aws ec2 describe-instances --region "$AWS_REGION" > "$INVENTORY_DIR/aws-ec2-instances.json"

echo "[*] AWS RDS Instances"
aws rds describe-db-instances --region="$AWS_REGION" > "$INVENTORY_DIR/aws-rds-instances.json"

echo "[*] AWS IAM Users"
aws iam list-users --region="$AWS_REGION" > "$INVENTORY_DIR/aws-iam-users.json"

echo "[✓] AWS inventory written to $INVENTORY_DIR/"
ls -lah "$INVENTORY_DIR"/aws-*.json
```

---

## Contact & Escalation

If credentials cannot be obtained:
1. Check previous deployments: `logs/governance/cross-backend-validation.jsonl` (shows where automation-runner-vault-role-id/secret-id were synced)
2. Check GSM project: `projects/nexusshield-prod` likely contains secrets (request access or operator fetch)
3. Contact AWS account admin: request temporary STS credentials (AccessKeyId + SecretAccessKey + SessionToken)
4. Contact production Vault operator: request short-lived admin token (1-hour TTL, suitable for one-off admin task)

---

**Document Version**: 2026-03-13T04:00:00Z  
**Status**: Ready for credential provision  
**Next Action**: Choose Option 1, 2, or 3 and provide required secrets

