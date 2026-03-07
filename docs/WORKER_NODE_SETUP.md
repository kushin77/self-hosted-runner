# Worker Node (192.168.168.42) Setup & Deployment Guide

**Status**: ✅ Production Worker Node  
**Last Updated**: 2026-03-07  
**Maintained by**: Automation Team  

---

## Quick Reference

| Property | Value |
|----------|-------|
| **IP Address** | `192.168.168.42` |
| **SSH User** | `akushnir` (primary), `cloud` (alternative) |
| **SSH Command** | `ssh akushnir@192.168.168.42` |
| **SSH Key** | `$DEPLOY_SSH_KEY` (GitHub secret) |
| **Role** | Production workload deployment target |
| **Operating System** | Linux (Ubuntu/Debian) |

---

## Services Running on Worker Node

| Service | Port | Health Check | Status |
|---------|------|--------------|--------|
| Alertmanager | 9093 | `curl http://192.168.168.42:9093/-/healthy` | ✅ Active |
| Prometheus | 9090 | `curl http://192.168.168.42:9090/metrics` | ✅ Active |
| Portal UI | 3919 | `curl http://192.168.168.42:3919` | ✅ Active |
| Managed-Auth API | 8080/4000 | `curl http://192.168.168.42:8080/health` or `:4000/health` | ✅ Active |
| MinIO | 9000 | `nc -zv 192.168.168.42 9000` | ✅ Active |
| Vault (local) | 8200 | `curl http://127.0.0.1:8200/v1/sys/health` (on local 192.168.168.42) | ✅ Active |

---

## SSH Access & Prerequisites

### Step 1: Verify SSH Connectivity

```bash
ssh akushnir@192.168.168.42 "echo ✓ SSH access confirmed"
```

Expected output:
```
✓ SSH access confirmed
```

### Step 2: Verify Deploy Key is Configured

The `DEPLOY_SSH_KEY` GitHub repository secret must contain the private key for SSH authentication.

**To check if key is set (CI/CD context):**
```bash
if [ -z "$DEPLOY_SSH_KEY" ]; then 
  echo "ERROR: DEPLOY_SSH_KEY not set in GitHub secrets"
  exit 1
fi
```

**To manually set the key locally (development):**
```bash
export DEPLOY_SSH_KEY=$(cat ~/.ssh/deploy_id_rsa)
# Or copy from AWS Secrets Manager, 1Password, etc.
```

### Step 3: Configure Ansible SSH Key

When running Ansible playbooks locally:

```bash
# Create temp key file
mkdir -p /tmp/ansible
echo "$DEPLOY_SSH_KEY" > /tmp/ansible/deploy_id_rsa
chmod 600 /tmp/ansible/deploy_id_rsa

# Use in ansible-playbook commands
ANSIBLE_SSH_KEY_PATH=/tmp/ansible/deploy_id_rsa
ansible-playbook -i ansible/inventory/production \
  ansible/playbooks/deploy-rotation.yml \
  --private-key="$ANSIBLE_SSH_KEY_PATH"
```

---

## Ansible Inventories

### Staging Inventory (Local/Canary)
**File**: `ansible/inventory/canary`

```
[canary]
runner1 ansible_host=localhost ansible_connection=local dev_skip_become=true

[all:vars]
ansible_user=ubuntu
ansible_become=true
runner_repo_url=https://github.com/kushin77/self-hosted-runner
runner_name_prefix=eiq-runner
workdir=/opt/actions-runner
```

**Use for**: Local/canary testing (no SSH needed; local connection)

---

### Production Inventory (Worker Node)
**File**: `ansible/inventory/production`

```
[production]
# Uncomment and set for actual production deployments
# 192.168.168.42 ansible_user=cloud ansible_become=true

# Alternative (if inventory file doesn't exist, create it):
[runners]
worker1 ansible_host=192.168.168.42 ansible_user=akushnir ansible_become=true

[all:vars]
ansible_user=akushnir
ansible_become=true
runner_repo_url=https://github.com/kushin77/self-hosted-runner
runner_name_prefix=eiq-runner
workdir=/opt/actions-runner
```

**Use for**: Production deployments to 192.168.168.42

---

## Running Playbooks Against Worker Node

### Example 1: Deploy Rotation (Vault Integration)

```bash
# Local execution with private key
ANSIBLE_SSH_KEY_PATH=/tmp/ansible/deploy_id_rsa
ansible-playbook -i ansible/inventory/production \
  ansible/playbooks/deploy-rotation.yml \
  --private-key="$ANSIBLE_SSH_KEY_PATH" \
  -vvv  # verbose output
```

### Example 2: SSH Key Provisioning

```bash
ansible-playbook -i ansible/inventory/production \
  ansible/playbooks/auto-ssh-key-provisioning.yml \
  --private-key="$ANSIBLE_SSH_KEY_PATH" \
  -f target_environment=production
```

### Example 3: Health Check / Idempotence Verification

```bash
# Run twice to check idempotency (no changes on second run)
ansible-playbook -i ansible/inventory/production \
  ansible/playbooks/deploy-rotation.yml \
  --private-key="$ANSIBLE_SSH_KEY_PATH" \
  --check  # dry-run first
```

---

## Health Checks & Verification

### Full Service Health

```bash
# Via SSH
ssh akushnir@192.168.168.42 << 'EOF'
echo "=== Available Services ==="
ps aux | grep -E "alertmanager|prometheus|node|vault" | grep -v grep
echo ""
echo "=== Network Ports ==="
ss -tlnp | grep LISTEN
echo ""
echo "=== Service Endpoints ==="
curl -s http://localhost:9093/-/healthy | head -c 100 && echo ""
curl -s http://localhost:9090/metrics | head -c 100 && echo ""
curl -s http://localhost:8080/health 2>/dev/null | head -c 100 && echo ""
EOF
```

### Individual Checks

```bash
# Alertmanager
curl -fsS http://192.168.168.42:9093/-/healthy

# Prometheus metrics
curl -fsS http://192.168.168.42:9090/metrics | head -20

# Portal
curl -fsS -I http://192.168.168.42:3919 | head -5

# MinIO connectivity
nc -zv 192.168.168.42 9000
```

---

## Deployment Workflow (Phase 2)

### Full End-to-End Flow

1. **Artifact Registry Automation** (`.github/workflows/artifact-registry-automation.yml`)
   - Builds and pushes images to `ghcr.io`
   - Signs with cosign (keyless OIDC)
   - Stores metadata artifact

2. **Canary Deployment** (`.github/workflows/canary-deployment.yml`)
   - Deploys to canary inventory (`ansible/inventory/canary`, runs local)
   - Runs health checks
   - Simulates failure/rollback logic (optional)

3. **Progressive Rollout** (`.github/workflows/progressive-rollout.yml`)
   - Dispatches to production inventory
   - Supports `staged`, `all-at-once`, `blue-green` strategies
   - Per-batch health verification
   - Auto-rollback on failure (creates P1 issue)

4. **Deployment Metrics** (`.github/workflows/deployment-metrics-aggregator.yml`)
   - Collects metrics from prior steps
   - Uploads as JSON artifact
   - Posts summary to GitHub Issue #1313

---

## Manual Deployment (For Ops/Debugging)

### Scenario 1: Deploy Alertmanager Config to Production

```bash
# Fetch latest config from GCP Secret Manager
gcloud secrets versions access latest --secret=alertmanager-config > /tmp/alertmanager.yml

# Copy to worker node
scp -i ~/.ssh/deploy_id_rsa /tmp/alertmanager.yml akushnir@192.168.168.42:/tmp/

# SSH and activate via Ansible
ssh akushnir@192.168.168.42
ANSIBLE_SSH_KEY_PATH=/tmp/ansible/deploy_id_rsa
sudo -E ansible-playbook -i localhost, \
  ansible/playbooks/deploy-rotation.yml \
  --private-key="$ANSIBLE_SSH_KEY_PATH"
```

### Scenario 2: Rollback on Failure

```bash
# If a deployment fails, restore from backup
ssh akushnir@192.168.168.42 "sudo systemctl restart alertmanager"

# Or run rollback playbook
ansible-playbook -i ansible/inventory/production \
  ansible/playbooks/rollback.yml \
  --private-key=/tmp/ansible/deploy_id_rsa
```

### Scenario 3: Test Idempotency

```bash
# Run playbook in check mode (dry-run)
ansible-playbook -i ansible/inventory/production \
  ansible/playbooks/deploy-rotation.yml \
  --check

# Then run again to apply (should be no changes)
ansible-playbook -i ansible/inventory/production \
  ansible/playbooks/deploy-rotation.yml
```

---

## Troubleshooting

### SSH Permission Denied

**Symptom**: `Permission denied (publickey).`

**Solution**:
1. Verify the private key is correct:
   ```bash
   ssh-keygen -lf ~/.ssh/deploy_id_rsa
   ```
2. Check if the public key is installed on 192.168.168.42:
   ```bash
   ssh akushnir@192.168.168.42 "grep $(cat ~/.ssh/deploy_id_rsa.pub | awk '{print $3}') ~/.ssh/authorized_keys"
   ```
3. If public key is missing, install it via ops procedure or AWS Systems Manager.

### Ansible Host Unreachable

**Symptom**: `UNREACHABLE! => {"changed": false, "msg": "Failed to connect to the host via ssh: ...`

**Solution**:
1. Test raw SSH:
   ```bash
   ssh -v akushnir@192.168.168.42 "echo OK"
   ```
2. If raw SSH works, verify Ansible can find the inventory:
   ```bash
   ansible -i ansible/inventory/production all -m ping
   ```
3. If inventory issue, check file exists:
   ```bash
   ls -la ansible/inventory/production
   ```

### Services Not Responding

**Symptom**: `curl: (7) Failed to connect to 192.168.168.42 port 9093: Connection refused`

**Solution**:
1. Check if service is running:
   ```bash
   ssh akushnir@192.168.168.42 "sudo systemctl status alertmanager"
   ```
2. Check logs:
   ```bash
   ssh akushnir@192.168.168.42 "sudo journalctl -u alertmanager -n 50"
   ```
3. Verify network connectivity:
   ```bash
   ping 192.168.168.42
   nc -zv 192.168.168.42 9093
   ```

---

## GitHub Actions Integration

### Dispatch Canary Deployment

```bash
gh workflow run .github/workflows/canary-deployment.yml \
  --repository kushin77/self-hosted-runner \
  --ref main \
  -f playbook=ansible/playbooks/deploy-rotation.yml \
  -f inventory=ansible/inventory/canary \
  -f canary_limit=canary \
  -f health_endpoint=http://localhost:9093/-/healthy
```

### Dispatch Progressive Rollout (to production)

```bash
gh workflow run .github/workflows/progressive-rollout.yml \
  --repository kushin77/self-hosted-runner \
  --ref main \
  -f strategy=staged \
  -f playbook=ansible/playbooks/deploy-rotation.yml \
  -f inventory=ansible/inventory/production \
  -f batches=batch1,batch2 \
  -f wait_seconds=60 \
  -f health_endpoint=http://192.168.168.42:9093/-/healthy
```

---

## Key Principles (Hands-Off Automation)

1. **Immutable**: All deployments use read-only file paths (`/usr/libexec`, `/etc`, etc.)
2. **Ephemeral**: Runtime state lives in `/run` (tmpfiles.d cleans on reboot)
3. **Idempotent**: Playbooks can be re-run safely; Ansible detects no changes
4. **No Ops**: Workflows are fully automated; operators only monitor (no manual steps)
5. **Hands-Off**: Errors trigger P1 issues; auto-rollback occurs; metrics collected automatically

---

## References

- **Alertmanager Deploy**: `ansible/playbooks/deploy-rotation.yml`
- **SSH Key Provisioning**: `.github/workflows/auto-ssh-key-provisioning.yml`
- **Canary Deployment**: `.github/workflows/canary-deployment.yml`
- **Progressive Rollout**: `.github/workflows/progressive-rollout.yml`
- **Deployment Metrics**: `.github/workflows/deployment-metrics-aggregator.yml`
- **Ansible Inventory**: `ansible/inventory/canary`, `ansible/inventory/production`
- **GCP Secret Manager**: Alertmanager config stored as `slack-webhook` and `alertmanager-config`

---

**For Copilot**: When deploying or testing against the production worker node, always:
1. SSH to `192.168.168.42` with `akushnir` user
2. Use `DEPLOY_SSH_KEY` from GitHub secrets in CI/CD contexts
3. Reference `ansible/inventory/production` for playbook targets
4. Verify all services are running via health endpoints before rollback/rollout decisions
5. Collect metrics and post summaries to GitHub issues
6. Create P1 issues on any deployment failures

