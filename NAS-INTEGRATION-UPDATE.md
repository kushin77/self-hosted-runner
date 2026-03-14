# NAS Integration Update - eiq-nas Repository

**Date**: March 14, 2026  
**Purpose**: Integrate new eiq-nas repository setup with existing self-hosted-runner infrastructure  
**Status**: Ready for Implementation  

---

## 📋 Architecture Overview

### New NAS Setup (eiq-nas)
The new repository at `https://github.com/kushin77/eiq-nas.git` provides:

1. **Service Account Infrastructure** (`svc-git`)
   - System user for passwordless git operations
   - SSH keys (ED25519) stored in GCP Secret Manager (GSM)
   - Systemd service for automatic key fetching at boot

2. **Bootstrap Automation**
   - `gsm-bootstrap.sh` - Complete GCP setup (one-time)
   - `fetch-svc-git-key.sh` - Key retrieval with gcloud
   - `complete-bootstrap.sh` - End-to-end automation
   - `fast-gcp-setup.sh` - Streamlined setup

3. **GitHub Integration**
   - Deploy key setup (write access enabled)
   - Passwordless push/pull operations
   - Automated credential management via GSM

### Current Setup (self-hosted-runner)
- NAS sync via worker nodes (30-min cycle)
- Health checks (15-min cycle)
- Dev node push capability
- 4 phases deployed (core, enhancement, stress testing, monitoring)

---

## 🚀 Migration Strategy

### Phase 1: Setup new NAS Service Account (One-Time)

```bash
# 1. Clone eiq-nas and review setup
cd /tmp
git clone https://github.com/kushin77/eiq-nas.git
cd eiq-nas

# 2. Authenticate to GCP (if not already done)
gcloud auth login
# or with service account:
gcloud auth activate-service-account --key-file=~/.gcp-key.json

# 3. Run bootstrap (creates GSM secret, uploads SSH key)
cd /home/kushin77/svc-git
bash gsm-bootstrap.sh nexusshield-prod svc-git-ssh-key

# 4. Add public key to GitHub
# Copy from: /home/kushin77/svc-git/public_key.txt
# Add to: https://github.com/settings/ssh/new (or repo deploy keys)

# 5. Test push
sudo -u svc-git -H git -C /home/kushin77 push -u origin main
```

**Expected Output**: `Everything up-to-date`

### Phase 2: Update Worker Node Sync Scripts

Update [worker-node-nas-sync.sh](scripts/nas-integration/worker-node-nas-sync.sh) to use new NAS endpoint:

```bash
# Current configuration (update this)
NAS_HOST="192.168.168.100"
SYNC_PATH="/nas/iac"

# New configuration (integrate with eiq-nas)
NAS_GIT_REPO="git@github.com:kushin77/eiq-nas.git"
NAS_LOCAL_PATH="/home/automation/eiq-nas"
NAS_HOST="192.168.168.100"  # Keep for SSH tunneling if needed
```

### Phase 3: Update Dev Node Push Scripts

Update [dev-node-nas-push.sh](scripts/nas-integration/dev-node-nas-push.sh) to integrate eiq-nas:

```bash
# Use the new svc-git service account for pushes
PUSH_USER="svc-git"
PUSH_IDENTITY="/home/svc-git/.ssh/id_ed25519"  # From GSM at runtime

# Push to eiq-nas instead of direct NAS
git -C /home/kushin77 push origin main
```

### Phase 4: Update Health Checks

Update [healthcheck-worker-nas.sh](scripts/nas-integration/healthcheck-worker-nas.sh) to verify eiq-nas:

```bash
# New health checks
✅ eiq-nas git repository connectivity
✅ svc-git SSH key accessibility from GSM
✅ GitHub SSH authentication status
✅ NAS local cache synchronization
✅ Systemd svc-git-key service status
```

### Phase 5: Update Monitoring & Alerts

Update Prometheus rules to monitor new infrastructure:

```yaml
# New metrics
- alert: EiqNasGitSync
  expr: time() - timestamp(eiq_nas_last_sync) > 3600
  for: 5m
  
- alert: SvcGitKeyFetchFailure
  expr: svc_git_key_fetch_errors_total > 0
  
- alert: GithubSSHAuthFailure
  expr: github_ssh_auth_status == 0
```

---

## 📊 Integration Points

### 1. Worker Node Configuration

**File**: `/etc/systemd/system/nas-worker-sync.service`

```ini
[Service]
ExecStart=/home/automation/scripts/nas-integration/worker-node-nas-sync-updated.sh
Environment="NAS_GIT_REPO=git@github.com:kushin77/eiq-nas.git"
Environment="NAS_LOCAL_PATH=/home/automation/eiq-nas"
Environment="GCP_PROJECT=nexusshield-prod"
```

### 2. Service Account Integration

**Create systemd service for automation user** to fetch svc-git credentials:

```bash
# On worker node
sudo cp /tmp/eiq-nas/svc-git/svc-git-key.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable svc-git-key.service
sudo systemctl start svc-git-key.service
```

### 3. GSM Secret Access

**Automation user needs GSM Secret Accessor role**:

```bash
gcloud projects add-iam-policy-binding nexusshield-prod \
  --member=serviceAccount:automation@worker \
  --role=roles/secretmanager.secretAccessor
```

### 4. Git Credential Provider

**Configure git to use GSM for credentials**:

```bash
# On automation user's shell
export GOOGLE_APPLICATION_CREDENTIALS=/var/lib/automation/.gcp-key.json

# Test access
gcloud secrets versions access latest --secret=svc-git-ssh-key
```

---

## 🔐 Security Updates

### Current (Self-Hosted-Runner)
- ✅ Credentials from GSM/Vault
- ✅ SSH keys for authentication
- ✅ Ephemeral execution isolation
- ⚠️ NAS access via direct SSH

### New (eiq-nas)
- ✅ Credentials from GSM/Vault (same)
- ✅ ED25519 SSH keys (cryptographically strong)
- ✅ Ephemeral execution isolation (same)
- ✅ GitHub API as central coordination
- ✅ Immutable git history as audit trail
- ✅ Systemd service with automatic key refresh

**Security Improvement**: Shift from direct NAS SSH to git-backed versioning with immutable audit trail.

---

## 📈 Operational Changes

### NAS Access Pattern

**Before**:
```
Worker → SSH → NAS (192.168.168.100)
Dev → SSH → NAS
```

**After**:
```
Worker → Git Clone → eiq-nas (192.168.168.100) → GitHub
Dev → Git Push → eiq-nas → GitHub (svc-git account)
```

### Credentials Flow

**Before**:
```
GSM → SSH Key → Direct NAS Access
```

**After**:
```
GSM → svc-git SSH Key → GitHub Deploy Key → eiq-nas Git Repo
```

---

## ✅ Implementation Checklist

- [ ] **Phase 1**: Setup eiq-nas svc-git account
  - [ ] Authenticate to GCP
  - [ ] Run gsm-bootstrap.sh
  - [ ] Add public key to GitHub
  - [ ] Test git push/pull

- [ ] **Phase 2**: Update worker node sync scripts
  - [ ] Modify worker-node-nas-sync.sh
  - [ ] Test git clone on worker
  - [ ] Verify 30-min sync cycle

- [ ] **Phase 3**: Update dev node push scripts
  - [ ] Modify dev-node-nas-push.sh
  - [ ] Test git push as svc-git
  - [ ] Verify automation user access

- [ ] **Phase 4**: Update health checks
  - [ ] Add git repository checks
  - [ ] Add svc-git key availability check
  - [ ] Monitor GitHub SSH auth

- [ ] **Phase 5**: Update monitoring
  - [ ] Add eiq-nas sync metrics
  - [ ] Add svc-git key fetch metrics
  - [ ] Configure Prometheus scrapers

- [ ] **Phase 6**: Rollback plan
  - [ ] Document fallback to direct NAS
  - [ ] Keep current scripts as backup
  - [ ] Test recovery procedure

---

## 🎯 New Scripts Required

### 1. worker-node-nas-sync-updated.sh

```bash
#!/bin/bash
set -euo pipefail

NAS_GIT_REPO="git@github.com:kushin77/eiq-nas.git"
NAS_LOCAL_PATH="/home/automation/eiq-nas"
AUDIT_LOG="/var/log/nas-sync-updated.log"

# Fetch credentials from GSM (via svc-git-key.service)
export SSH_AUTH_SOCK=/run/svc-git-key-agent.sock

# Clone/update eiq-nas
if [ ! -d "$NAS_LOCAL_PATH" ]; then
  git clone "$NAS_GIT_REPO" "$NAS_LOCAL_PATH"
else
  git -C "$NAS_LOCAL_PATH" pull origin main
fi

# Audit trail
echo "$(date): Sync completed, $(find $NAS_LOCAL_PATH -type f | wc -l) files" >> "$AUDIT_LOG"
```

### 2. dev-node-nas-push-updated.sh

```bash
#!/bin/bash
set -euo pipefail

NAS_GIT_REPO_PATH="/home/kushin77"
PUSH_IDENTITY="/home/kushin77/.ssh/id_ed25519"

# Use svc-git credentials for push
sudo -u svc-git -H git -C "$NAS_GIT_REPO_PATH" push origin main

echo "Push to eiq-nas completed: $(date)"
```

### 3. healthcheck-updated.sh

```bash
#!/bin/bash

# Check eiq-nas git repository
git -C /home/automation/eiq-nas fetch origin >/dev/null 2>&1 && \
  echo "✅ eiq-nas git sync: OK" || \
  echo "❌ eiq-nas git sync: FAILED"

# Check svc-git key accessibility
gcloud secrets versions access latest --secret=svc-git-ssh-key >/dev/null 2>&1 && \
  echo "✅ svc-git key access: OK" || \
  echo "❌ svc-git key access: FAILED"

# Check GitHub SSH
sudo -u svc-git -H ssh -T git@github.com >/dev/null 2>&1 && \
  echo "✅ GitHub SSH auth: OK" || \
  echo "⚠️  GitHub SSH auth: CHECK"

# Check systemd service
sudo systemctl is-active svc-git-key.service >/dev/null 2>&1 && \
  echo "✅ svc-git-key service: ACTIVE" || \
  echo "❌ svc-git-key service: INACTIVE"
```

---

## 📞 Fallback & Rollback

If eiq-nas integration encounters issues:

1. **Immediate**: Switch back to current direct NAS scripts
   ```bash
   systemctl stop nas-worker-sync.timer
   systemctl start nas-worker-sync.timer  # uses old script
   ```

2. **Temporary**: Use direct SSH while troubleshooting
   ```bash
   rsync -avz automation@192.168.168.100:/nas/iac /home/automation/
   ```

3. **Recovery**: Test each component independently
   - [ ] GSM access
   - [ ] svc-git key fetch
   - [ ] GitHub SSH auth
   - [ ] Git clone/push

---

## 🎓 Compliance

### Updated Operational Mandates

✅ **Immutable**: Git commit SHA as version tracking  
✅ **Ephemeral**: Service account key fetched at runtime  
✅ **Idempotent**: Git pull/push are idempotent operations  
✅ **Hands-Off**: Systemd timers + svc-git-key service  
✅ **Credentials**: GSM-backed SSH keys (improved)  
✅ **Direct Deploy**: Git-based automation (GitHub is canonical source)  
✅ **No-Ops**: Systemd service handles key rotation  

---

## 📊 Success Metrics

After migration, verify:

- ✅ Worker nodes syncing via `git clone eiq-nas`
- ✅ Dev nodes pushing via svc-git service account
- ✅ Health checks passing (eiq-nas connectivity + svc-git key)
- ✅ Audit trail complete (git log shows all operations)
- ✅ GSM secrets accessible (no local credential storage)
- ✅ No manual intervention required (fully automated)
- ✅ Prometheus metrics updated and alerting

---

## 🚀 Timeline

- **T+0**: Review eiq-nas repository structure
- **T+1h**: Setup svc-git and GitHub integration
- **T+2h**: Update and test new sync scripts
- **T+3h**: Deploy to worker nodes (staged rollout)
- **T+4h**: Deploy to dev nodes
- **T+5h**: Verify health checks and monitoring
- **T+6h**: Full operational activation

---

## 📝 Notes

- All existing compliance mandates maintained
- Enhanced security via GitHub as coordination layer
- Improved audit trail through git history
- Zero impact on current 24/7 automation
- Rollback capability preserved throughout
- All credentials continue to come from GSM only

---

**Status**: Ready for implementation  
**Authorization**: Proceed with phased integration  
**Owner**: automation@worker on 192.168.168.42
