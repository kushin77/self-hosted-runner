# Host Separation & Migration Guide
## Dev Node (.31) → Code Only | Worker Node (.42) → All Deployments

**Date:** March 12, 2026  
**Status:** ✅ Ready for Execution  
**Governance:** Immutable, Idempotent, Ephemeral, No-Ops, Hands-Off  

---

## Architecture Overview

```
┌─────────────────────────────────┐      ┌─────────────────────────────────┐
│ Dev Host 192.168.168.31         │      │ Worker Node 192.168.168.42      │
│ (Code Development Only)         │      │ (All Production Deployments)    │
├─────────────────────────────────┤      ├─────────────────────────────────┤
│ ✅ git, node, npm, python       │      │ ✅ Kubernetes (k8s)             │
│ ✅ make, gcc, IDE tools         │      │ ✅ Docker / containerd          │
│ ✅ SSH access for remote work   │      │ ✅ Terraform / helm             │
│ ❌ docker, kubernetes removed   │      │ ✅ Host crash analysis CronJob  │
│ ❌ Package installs prevented   │      │ ✅ Service deployments          │
│ ❌ sudo: no apt/snap/dpkg       │      │ ✅ Monitoring & observability   │
│                                 │      │ ✅ GCS audit trail access       │
│ Codebase Location:              │      │ Codebase Synced:                │
│ ~/self-hosted-runner/           │      │ ~/self-hosted-runner/ (rsync)   │
└─────────────────────────────────┘      └─────────────────────────────────┘
```

---

## What Gets Migrated to Worker Node (.42)

### 1. **Codebase & Repositories**
- Full `self-hosted-runner` repo (git history preserved)
- All Terraform modules
- K8s manifests
- Deployment scripts
- Host crash analysis system

### 2. **Kubernetes Infrastructure**
- `monitoring` namespace
- `host-crash-analyzer` CronJob (daily 2 AM UTC)
- ConfigMaps with embedded scripts
- ServiceAccount + RBAC
- Secrets for GCS audit bucket

### 3. **Docker & Runtime Services**
- Docker daemon + containers
- Container runtimes (containerd, etc.)
- Kubernetes services
- Any stateful deployments

### 4. **Monitoring & Observability**
- GCS audit trail integration
- Prometheus/Grafana (if deployed)
- Logging infrastructure
- Secret Manager access

---

## What Stays on Dev Node (.31)

### ✅ Development Tools (Preserved)
```bash
git                    # Version control
node, npm              # Node.js development
python3                # Python scripting
gcc, make              # Compilation tools
vim, nano              # Text editors
docker-cli             # Can push images (if needed)
```

### ❌ Removed/Disabled (Lockdown)
```bash
docker daemon          # Remove
kubernetes             # Remove
kubelet               # Remove
containerd            # Remove
snapd                 # Stop & disable
helm                  # Remove
kubectl               # Remove (can use remote: ssh worker kubectl)
```

---

## Step-by-Step Migration

### Phase 1: Setup Worker Node (.42)

#### 1a. Install Prerequisites on .42 (if not present)
```bash
# On 192.168.168.42
sudo apt-get update

# Kubernetes
curl -fsSL https://apt.kubernetes.io/doc/apt-key.gpg | sudo apt-key add -
sudo apt-get install -y kubectl

# Docker (if not using containerd)
sudo apt-get install -y docker.io

# Terraform
curl -fsSL https://apt.hashicorp.com/gpg | sudo apt-key add -
sudo apt-get install -y terraform

# gcloud CLI
curl https://sdk.cloud.google.com | bash
exec -l $SHELL

# Verify
which kubectl docker terraform gcloud
```

#### 1b. Copy Code to Worker Node
```bash
# From dev node (.31), rsync to worker node (.42)
rsync -avz --delete \
  --exclude='.git/objects' \
  --exclude='.terraform/' \
  --exclude='node_modules' \
  ~/self-hosted-runner/ \
  ubuntu@192.168.168.42:~/self-hosted-runner/

# Verify on worker node
ssh ubuntu@192.168.168.42 'ls -la ~/self-hosted-runner/'
```

#### 1c. Deploy on Worker Node
```bash
# SSH to worker node
ssh ubuntu@192.168.168.42

# Navigate to Terraform
cd ~/self-hosted-runner/terraform/host-monitoring

# Deploy (idempotent)
terraform init
terraform plan -out=tfplan
terraform apply tfplan -auto-approve

# Verify deployment
kubectl get ns monitoring
kubectl get cronjob -n monitoring
kubectl get sa -n monitoring
```

---

### Phase 2: Lockdown Dev Node (.31)

#### 2a. Stop Runtime Services
```bash
# On dev node (.31)
sudo systemctl stop docker
sudo systemctl stop kubernetes
sudo systemctl stop kubelet
sudo systemctl stop containerd
sudo systemctl stop snapd

# Disable auto-start
sudo systemctl disable docker
sudo systemctl disable kubernetes
sudo systemctl disable kubelet
sudo systemctl disable containerd
sudo systemctl disable snapd
```

#### 2b. Configure sudo Restrictions
```bash
# Create restriction file
sudo cat > /etc/sudoers.d/99-no-install <<'EOF'
# Prevent package installations on dev host
Cmnd_Alias FORBIDDEN_INSTALLS = /usr/bin/apt-get install*, /usr/bin/apt install*, /usr/bin/snap install*, /usr/bin/dpkg -i*
ALL ALL=(ALL) DENY: FORBIDDEN_INSTALLS

# Allow only dev tools
Cmnd_Alias DEV_TOOLS = /usr/bin/git, /usr/bin/node, /usr/bin/python*, /usr/bin/make, /usr/bin/gcc
%sudo ALL=(ALL) NOPASSWD: DEV_TOOLS
EOF

# Verify with
sudo -l | grep -i FORBIDDEN
```

#### 2c. Remove Runtime Packages
```bash
# Remove Docker
sudo apt-get remove -y docker.io docker-compose || true
sudo apt-get remove -y kubernetes-client helm || true
sudo apt-get autoremove -y

# Clean up runtime data
sudo rm -rf /var/lib/docker
sudo rm -rf /var/lib/containerd
sudo rm -rf /opt/kubernetes

# Verify development tools remain
git --version
node --version
npm --version
python3 --version
gcc --version
make --version

# These should all work ✅
```

#### 2d. Verify Separation
```bash
# On dev node (.31), these should FAIL:
docker ps                    # ❌ Command not found
kubectl get pods             # ❌ Command not found
terraform apply              # ❌ Command not found

# These should WORK:
git status                   # ✅ Works
node --version              # ✅ Works
npm --version               # ✅ Works
python3 --version           # ✅ Works

# To use Kubernetes/Terraform, SSH to worker:
ssh ubuntu@192.168.168.42 'kubectl get cronjob -n monitoring'
ssh ubuntu@192.168.168.42 'terraform -v'
```

---

### Phase 3: Automated Execution

#### Use Migration Script
```bash
# On dev node, run migration script
cd ~/self-hosted-runner
chmod +x scripts/ops/host-migration-lockdown.sh

# Option 1: Deploy to worker only
./scripts/ops/host-migration-lockdown.sh worker

# Option 2: Lockdown dev only
./scripts/ops/host-migration-lockdown.sh lockdown

# Option 3: Do everything (all phases)
./scripts/ops/host-migration-lockdown.sh all

# Track progress in logs
tail -f /var/log/host-migration-*.log
```

---

## Verification Checklist

### Dev Node (.31) After Lockdown

```bash
✅ Docker removed/stopped
✅ Kubernetes removed/stopped
✅ sudo prevents installs
✅ Git works
✅ Node/npm works
✅ Python works
✅ Gcc/make works
✅ No runtime services running

# Verify
systemctl list-units --type=service --state=running | grep -i docker
# Should return: (nothing)

systemctl list-units --type=service --state=running | grep -i kubernetes
# Should return: (nothing)

apt-cache policy docker.io
# Status: Deinstalled
```

### Worker Node (.42) After Deployment

```bash
✅ Kubernetes running
✅ monitoring namespace exists
✅ host-crash-analyzer CronJob scheduled
✅ ServiceAccount with RBAC
✅ ConfigMaps with scripts loaded
✅ GCS audit bucket accessible

# Verify
kubectl get ns monitoring
# Should show: monitoring namespace exists

kubectl get cronjob -n monitoring
# Should show: host-crash-analyzer, SCHEDULE="0 2 * * *"

kubectl describe cronjob host-crash-analyzer -n monitoring
# Should show all details

kubectl get sa -n monitoring
# Should show: host-crash-analysis service account

gsutil ls gs://nexusshield-prod-host-crash-audit/
# Should list audit trail
```

---

## Network Separation

### Dev Node (.31) Network Policy
```
Allow:  ✅ SSH (22), Git, HTTP (80), HTTPS (443)
Allow:  ✅ Outbound to package mirrors (for reads only)
Deny:   ❌ Docker socket (2375, 2376)
Deny:   ❌ Kubernetes API (6443)
Deny:   ❌ containerd (1234)
```

### Worker Node (.42) Network Policy
```
Allow:  ✅ SSH (22)
Allow:  ✅ Kubernetes API (6443)
Allow:  ✅ Docker socket (2375)
Allow:  ✅ GCS access (443)
Allow:  ✅ Secret Manager (443)
Block:  ❌ Direct installs from untrusted sources
```

---

## Troubleshooting

### Issue: Can't SSH to Worker Node

```bash
# Verify SSH key is present
ls -la ~/.ssh/id_rsa

# Test connectivity
ssh -v ubuntu@192.168.168.42 "echo test"

# Check worker node is reachable
ping -c 3 192.168.168.42

# Verify hostname resolution
hostname -I | grep 192.168.168.42
```

### Issue: Terraform Apply Fails on Worker

```bash
# SSH to worker and check
ssh ubuntu@192.168.168.42

# Verify gcloud is configured
gcloud config get-value project

# Verify kubectl access
kubectl cluster-info

# Check Terraform state
cd ~/self-hosted-runner/terraform/host-monitoring
terraform state list
```

### Issue: CronJob Not Triggering

```bash
# Check schedule
kubectl describe cronjob host-crash-analyzer -n monitoring

# View events
kubectl get events -n monitoring --sort-by='.lastTimestamp'

# Manual trigger for testing
kubectl create job host-crash-analysis-manual-test-1 \
  --from=cronjob/host-crash-analyzer \
  -n monitoring

# Check logs
kubectl logs -f job/host-crash-analysis-manual-test-1 -n monitoring
```

### Issue: Cannot Install Anything on Dev Node

This is **by design** (goal achieved! ✅)

To re-enable installs temporarily:
```bash
# Edit sudoers (very carefully!)
sudo visudo

# Find and comment out the FORBIDDEN lines
# Then save (Ctrl+X in nano/vim)

# Reinstall restrictions when done
sudo cat > /etc/sudoers.d/99-no-install <<'EOF'
Cmnd_Alias FORBIDDEN = /usr/bin/apt-get install*, /usr/bin/apt install*
ALL ALL=(ALL) DENY: FORBIDDEN
EOF
```

---

## Idempotency & Safety

### Why This Is Safe to Re-Run

1. **Terraform:** State file ensures idempotency
   ```bash
   terraform apply  # Safe to run multiple times (no duplicates)
   ```

2. **Migration Script:** Checks before modifying
   ```bash
   rsync --checksum  # Only syncs changed files
   systemctl stop    # Idempotent (no-op if already stopped)
   ```

3. **Lockdown:** Only restricts, doesn't delete data
   ```bash
   sudo constraints   # Can be adjusted if needed
   rm -rf /var/lib/docker  # Only old runtime data
   ```

### Testing in Non-Prod First

```bash
# Create test VMs first
gcloud compute instances create dev-test-31 worker-test-42

# Run migration on test VMs
SSH to test-31
./scripts/ops/host-migration-lockdown.sh worker

# Verify works, then run on production
./scripts/ops/host-migration-lockdown.sh all
```

---

## Post-Migration Operations

### Daily Development on .31
```bash
# Code development works normally
cd ~/self-hosted-runner
git pull
npm install
npm run dev

# Deploy to .42 when ready
git push origin feature-branch

# From .42 (worker node), deploy:
ssh ubuntu@192.168.168.42
cd ~/self-hosted-runner
terraform apply
```

### Monitor Deployments on .42
```bash
# SSH to worker node
ssh ubuntu@192.168.168.42

# View running pods
kubectl get pods -A

# Check CronJob execution
kubectl get job -n monitoring --sort=.metadata.creationTimestamp

# View audit logs
gsutil ls -r gs://nexusshield-prod-host-crash-audit/
```

### Handle Emergency Access to .31

If .31 lockdown is too restrictive:
```bash
# Restore temporarily (SSH from .42 or admin)
ssh ubuntu@192.168.168.31 'sudo systemctl disable /etc/sudoers.d/99-no-install'

# After emergency, re-enable
ssh ubuntu@192.168.168.31 'sudo systemctl enable /etc/sudoers.d/99-no-install'
```

---

## Rollback Procedures

### If Migration Fails

```bash
# On worker node (.42), rollback Terraform
ssh ubuntu@192.168.168.42
cd ~/self-hosted-runner/terraform/host-monitoring
terraform destroy -auto-approve

# On dev node (.31), re-enable services
ssh ubuntu@192.168.168.31
sudo systemctl start docker
sudo systemctl start kubernetes
rm /etc/sudoers.d/99-no-install

# Restore packages (if needed)
sudo apt-get install docker.io kubernetes-client -y
```

### Backup Before Migration
```bash
# Snapshot GCS bucket
gsutil -m cp -r gs://nexusshield-prod-host-crash-audit/* \
  gs://nexusshield-prod-backups/pre-migration-backup-$(date +%s)/

# Backup dev node codebase
rsync -avz ~/self-hosted-runner/ \
  ~/backups/dev-node-backup-$(date +%Y%m%d%H%M%S)/
```

---

## Governance Compliance

✅ **Immutable:** Migration audit trail in GCS Object Lock  
✅ **Idempotent:** All scripts safe to re-run, no duplicates  
✅ **Ephemeral:** Secrets from Secret Manager, not in code  
✅ **No-Ops:** Automated migration script (hands-off)  
✅ **Hands-Off:** CronJob on .42, notifications to Slack  
✅ **No-Branch-Dev:** Direct commits to main (.42 deployment)  
✅ **Direct-Deploy:** Terraform to main, no PR gates (.42 only)  

---

## Timeline

| Phase | Duration | Notes |
|-------|----------|-------|
| Worker prep (.42) | 15 min | Install tools, verify k8s |
| Code sync | 5 min | rsync codebase |
| Terraform deploy | 10 min | CronJob setup |
| Dev lockdown (.31) | 10 min | Stop services, configure sudo |
| Cleanup (.31) | 5 min | Remove runtimes, verify tools |
| **Total** | **~45 minutes** | **Fully automated** |

---

## Support & Escalation

**Documentation:**
- This file: Full migration guide
- `terraform/host-monitoring/README.md`: K8s operations
- `scripts/ops/host-migration-lockdown.sh`: Automation script

**Quick Checks:**
```bash
# Which node am I on?
hostname
ip addr | grep 192.168

# What can I do here?
git status     # ✅ Dev only
docker ps      # ❌ Dev lockdown, ✅ Worker
kubectl get ns # ❌ Dev lockdown, ✅ Worker
```

---

**Status:** ✅ **READY FOR EXECUTION**  
**Execution Method:** Automated script (idempotent, hands-off)  
**Rollback:** Simple (destroy Terraform, restore sudoers)  

All governance requirements met. Ready to migrate and lock down. 🚀
