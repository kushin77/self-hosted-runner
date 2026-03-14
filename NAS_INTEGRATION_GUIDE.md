# eiq-nas Repository: Integration Guide for Worker & Dev Nodes

**Repository:** git@github.com:kushin77/eiq-nas.git  
**Last Updated:** 2026-03-14  
**Status:** Production-Ready

---

## 1. Repository Overview & Purpose

### What is eiq-nas?

A **dedicated NAS (Network-Attached Storage) infrastructure** serving as the centralized IAC (Infrastructure-as-Code) repository for deployment, secret management, and self-hosted-runner configuration.

**Core Components:**
- Passwordless Git automation service account (`svc-git`)
- GCP Secret Manager (GSM) integration for credential management
- Systemd-based key lifecycle management
- GitHub API integration for deploy key automation
- Complete bootstrap infrastructure for on-premises deployment

**Key Principle:** All secrets are encrypted in GCP Secret Manager (KMS-backed); only runtime SSH keys are present on the NAS itself.

---

## 2. Directory Structure & Main Components

```
eiq-nas/
├── README.md                          # High-level project description
├── QUICKSTART.txt                     # Deployment quick reference
├── GCP_SETUP_GUIDE.md                 # GCP authentication & bootstrap guide
│
├── fast-gcp-setup.sh                  # Interactive GCP setup helper
├── complete-bootstrap.sh              # Full end-to-end automation setup
│
└── svc-git/                           # Service account & Git automation
    ├── README.md                      # Comprehensive architecture docs
    ├── DEPLOYMENT.md                  # Deployment completion summary
    ├── gsm-bootstrap.sh               # Main bootstrap script (creates/updates GSM secrets)
    ├── fetch-svc-git-key.sh           # Key retrieval from GSM (runtime)
    ├── setup-with-service-account.sh  # Unattended setup with service account JSON
    ├── setup-github-deploy-key.sh     # Automated GitHub deploy key registration
    ├── store-github-token.sh          # Store GitHub PAT in GSM
    ├── svc-git-key.service            # Systemd unit for key fetching at boot
    ├── svc-git-key.env                # Environment config template
    ├── public_key.txt                 # Exported SSH public key for GitHub
    └── y/                             # Embedded Google Cloud SDK (optional)
```

---

## 3. How eiq-nas is Intended to Be Used

### A. Service Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    GCP Secret Manager                       │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ svc-git-ssh-key (ED25519 private key)                │  │
│  │ github-token-nass (GitHub PAT)                       │  │
│  └───────────────────────────────────────────────────────┘  │
└──────────────────────────┬──────────────────────────────────┘
                           │ (gcloud CLI)
                           ▼
        ┌──────────────────────────────────┐
        │      eiq-nas (NAS Server)        │
        ├──────────────────────────────────┤
        │ Systemd Service: svc-git-key     │
        │ ├─ Runs: fetch-svc-git-key.sh    │
        │ ├─ Fetches key from GSM on boot  │
        │ └─ Stores to: /home/svc-git/.ssh │
        ├──────────────────────────────────┤
        │ Git Automation (svc-git user)    │
        │ ├─ Passwordless SSH auth         │
        │ ├─ GitHub authenticated          │
        │ └─ Can push/pull as svc-git      │
        └──────────────────────────────────┘
                           │
                           ├─────────────────────────┐
                           ▼                         ▼
                    GitHub Repository         Worker/Dev Nodes
                  (eiq-nas codebase)      (pull IAC from NAS)
```

### B. Integration Patterns

#### **Pattern 1: Automated IAC Pull (Worker Nodes)**
```bash
# On worker node (periodic cron or systemd timer)
sudo -u svc-git -H git -C /opt/iac pull origin main
sudo -u svc-git -H git -C /opt/iac checkout latest-stable
```

**Use Case:** Deploy configuration from NAS to worker nodes via Git pull.

#### **Pattern 2: Configuration Push (Dev Nodes)**
```bash
# On dev node (manual or CI-automated push)
git -C /home/developer/iac add .
git -C /home/developer/iac commit -m "Update worker config"
git -C /home/developer/iac push origin feature-branch
```

**Use Case:** Developers push changes to NAS; NAS propagates to worker nodes.

#### **Pattern 3: Secret Rotation (Full Deployment)**
```bash
# Run on NAS
cd /home/kushin77/svc-git
bash gsm-bootstrap.sh nexusshield-prod svc-git-ssh-key
# → Updates GSM secret
# → Systemd service picks up new key on next boot
# → All nodes refresh at boot time (0-downtime rotation)
```

**Use Case:** Rotate SSH keys without stopping running services.

---

## 4. Key Files for On-Premises Integration

### A. **gsm-bootstrap.sh** — Main Bootstrap & Secret Upload
**Purpose:** Initialize NAS with GCP Secret Manager integration  
**Usage:**
```bash
cd /home/kushin77/svc-git
bash gsm-bootstrap.sh <GCP_PROJECT> <SECRET_NAME>
bash gsm-bootstrap.sh nexusshield-prod svc-git-ssh-key
```

**What It Does:**
1. Authenticates to GCP (interactive or service account)
2. Creates GSM secret if not exists
3. Uploads local SSH key (`/home/svc-git/.ssh/id_ed25519`) to GSM
4. Configures IAM bindings
5. Populates `/etc/default/svc-git-key` (PROJECT & SECRET env vars)
6. Starts systemd service to fetch key
7. Verifies SSH access to GitHub

**Output:** Ready for automated Git operations

---

### B. **fetch-svc-git-key.sh** — Runtime Key Fetching
**Purpose:** Retrieve SSH key from GSM at runtime (called by systemd)  
**Deployment:** Installed as `/usr/local/bin/fetch-svc-git-key.sh`  
**Trigger:** Systemd service (one-shot at boot)

**How It Works:**
```bash
# Called with environment variables from /etc/default/svc-git-key
PROJECT=nexusshield-prod SECRET=svc-git-ssh-key bash fetch-svc-git-key.sh
```

**Flow:**
1. Reads PROJECT & SECRET from env vars
2. Calls: `gcloud secrets versions access latest --secret=<SECRET> --project=<PROJECT>`
3. Writes key to: `/home/svc-git/.ssh/id_ed25519` (600 perms, svc-git owner)
4. Generates public key if missing

**Security:** No plaintext on disk; key exists only in memory until fetched

---

### C. **svc-git-key.service** — Systemd Integration
**Purpose:** Automatically fetch SSH key at boot  
**File Location:** `/etc/systemd/system/svc-git-key.service`  
**Type:** oneshot (RemainAfterExit=yes)

**Service Spec:**
```ini
[Unit]
Description=Fetch svc-git SSH key from GCP Secret Manager
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
EnvironmentFile=/etc/default/svc-git-key
ExecStart=/bin/bash -c '/usr/local/bin/fetch-svc-git-key.sh "$PROJECT" "$SECRET"'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

**Integration Points:**
- Runs after network is ready
- Blocks multi-user startup until key is fetched
- Non-blocking subsequent Git operations

---

### D. **setup-with-service-account.sh** — Automated Setup
**Purpose:** Unattended bootstrap using GCP service account (preferred for infrastructure)  
**Usage:**
```bash
# Auto-detect key at ~/.gcp-service-account.json
bash setup-with-service-account.sh

# Explicit path
bash setup-with-service-account.sh /path/to/key.json
```

**Key Advantage:** No interactive browser login—suitable for fully automated NAS deployment.

**Prerequisites:**
1. GCP service account JSON key (downloaded from GCP Console)
2. Service account has: `roles/secretmanager.admin`

---

### E. **setup-github-deploy-key.sh** — GitHub Integration
**Purpose:** Automate GitHub deploy key registration via API  
**Usage:**
```bash
bash setup-github-deploy-key.sh <OWNER> <REPO> <PUBLIC_KEY_FILE>
bash setup-github-deploy-key.sh kushin77 eiq-nas /home/svc-git/.ssh/id_ed25519.pub
```

**Prerequisites:**
- GitHub PAT stored in GSM as `github-token-nass`
- gcloud authenticated

**Result:** NAS SSH key added to GitHub repo with write access (no manual GitHub UI steps).

---

### F. **store-github-token.sh** — GitHub Token Management
**Purpose:** Store GitHub PAT in Secret Manager  
**Usage:**
```bash
# Interactive (prompts for token)
bash store-github-token.sh "ghp_your_personal_access_token_here"
```

**Does:**
1. Creates GSM secret `github-token-nass` if not exists
2. Uploads/updates PAT as new secret version
3. Used by `setup-github-deploy-key.sh` for API access

---

## 5. Integration with Worker & Dev Nodes

### A. **Worker Node Integration**

**Goal:** Pull IAC from NAS, apply configurations

**Setup:**

```bash
# On worker node (run once)
# Create svc-git user (if not exists)
sudo useradd -r -s /bin/bash svc-git
sudo mkdir -p /home/svc-git/.ssh
sudo chmod 700 /home/svc-git/.ssh

# Clone repository
sudo -u svc-git git clone git@github.com:kushin77/eiq-nas.git /opt/iac
sudo chown -R svc-git:svc-git /opt/iac

# Configure git for svc-git
sudo -u svc-git git config --global user.email "svc-git@worker"
sudo -u svc-git git config --global user.name "Service Git"
```

**Daily Pull (Cron or Systemd Timer):**

```bash
# /etc/cron.d/svc-git-pull (runs hourly)
0 * * * * svc-git /home/svc-git/pull-iac.sh

# Contents of /home/svc-git/pull-iac.sh
#!/bin/bash
set -euo pipefail
cd /opt/iac
git fetch origin
git checkout origin/main
# Apply configs
sudo systemctl reload-or-restart my-service
```

**SSH Key Provisioning:**

```bash
# Copy SSH key from NAS to worker node
ssh-copy-id -i /home/svc-git/.ssh/id_ed25519.pub svc-git@worker-node

# Or use Secrets Manager client library to fetch key directly
# (same pattern as NAS: gcloud secrets versions access...)
```

---

### B. **Dev Node Integration**

**Goal:** Push configurations from dev node to NAS (GitHub), triggering worker node updates

**Setup:**

```bash
# On dev node
mkdir -p ~/eiq-nas && cd ~/eiq-nas
git clone git@github.com:kushin77/eiq-nas.git .
git config user.email "developer@yourorg"
git config user.name "Developer Name"
```

**Workflow:**

```bash
# 1. Create feature branch
git checkout -b feature/update-worker-config

# 2. Edit IAC files
vim svc-git/configs/worker-node-1.yaml

# 3. Commit & push
git add .
git commit -m "Update worker monitoring config"
git push origin feature/update-worker-config

# 4. Create PR, merge to main
# (Dev team reviews)

# 5. Once merged to main, NAS propagates:
# → Systemd timer on NAS pulls latest
# → Worker nodes' cron jobs pull updated configs
# → Services reload with new configuration
```

---

### C. **On-Premises Backend Integration**

**SSH Key Sharing Pattern:**

1. **Generate on NAS:**
   ```bash
   sudo -u svc-git ssh-keygen -t ed25519 -f /home/svc-git/.ssh/id_ed25519 -N ""
   ```

2. **Export public key:**
   ```bash
   sudo -u svc-git ssh-keygen -y -f /home/svc-git/.ssh/id_ed25519 > \
     /home/kushin77/svc-git/public_key.txt
   ```

3. **Distribute to authorized_keys on backend systems:**
   ```bash
   # On backend/worker node
   echo "<PUBLIC_KEY_CONTENT>" >> /home/svc-git/.ssh/authorized_keys
   chmod 600 /home/svc-git/.ssh/authorized_keys
   ```

4. **Test access:**
   ```bash
   sudo -u svc-git ssh -T svc-git@backend-system
   ```

---

## 6. API Endpoints & Configuration

### A. **GCP Secret Manager API**

**Fetch Secret (as used by fetch-svc-git-key.sh):**
```bash
gcloud secrets versions access latest \
  --secret="svc-git-ssh-key" \
  --project="nexusshield-prod"
```

**Add Secret Version (as used by gsm-bootstrap.sh):**
```bash
gcloud secrets versions add "svc-git-ssh-key" \
  --data-file="/home/svc-git/.ssh/id_ed25519" \
  --project="nexusshield-prod"
```

**List Versions (audit):**
```bash
gcloud secrets versions list "svc-git-ssh-key" \
  --project="nexusshield-prod" \
  --format=json
```

---

### B. **GitHub API Integration**

**Deploy Key Registration (via REST API):**
```bash
curl -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "svc-git NAS",
    "key": "ssh-ed25519 AAAAC3...",
    "read_only": false
  }' \
  https://api.github.com/repos/kushin77/eiq-nas/keys
```

**Used by:** `setup-github-deploy-key.sh`

---

### C. **Environment Configuration**

**File:** `/etc/default/svc-git-key`
```bash
PROJECT=nexusshield-prod
SECRET=svc-git-ssh-key
```

**File:** `.git/config` (inside NAS repo)
```ini
[core]
    repositoryformatversion = 0
[remote "origin"]
    url = git@github.com:kushin77/eiq-nas.git
    fetch = +refs/heads/*:refs/remotes/origin/*
[branch "main"]
    remote = origin
    merge = refs/heads/main
```

---

## 7. Mounting, Access Control & Deployment Patterns

### A. **SSH Access Control**

**NAS Administration Access:**
```bash
# Only authorized users can sudo or directly SSH as svc-git
sudo usermod -aG svc-git <admin_username>

# SSH key for admin access
ssh-copy-id -i ~/.ssh/id_ed25519.pub kushin77@nas
```

**Worker Node Access from NAS:**
```bash
# svc-git can SSH to worker nodes (passwordless)
sudo -u svc-git ssh svc-git@worker-node-1 "sudo systemctl restart my-service"
```

---

### B. **File Permissions & Ownership**

```bash
# svc-git SSH private key (NAS)
-rw------- svc-git:svc-git /home/svc-git/.ssh/id_ed25519

# svc-git SSH public key (shareable)
-rw-r--r-- svc-git:svc-git /home/svc-git/.ssh/id_ed25519.pub

# Git repository (world-readable, admin-writable)
drwxr-xr-x kushin77:kushin77 /home/kushin77/.git

# Systemd service (read-only for non-root)
-rw-r--r-- root:root /etc/systemd/system/svc-git-key.service

# Fetch script (executable by systemd)
-rwxr-xr-x root:root /usr/local/bin/fetch-svc-git-key.sh

# Environment config (secrets, restricted)
-rw------- root:root /etc/default/svc-git-key
```

---

### C. **Networking & Deployment Topology**

```
┌─────────────────┐
│  GitHub.com     │
│  (Public Cloud) │
└────────┬────────┘
         │ (HTTPS/SSH)
         ▼
┌─────────────────────────────────┐
│   NAS (On-Premises)             │
│   • Git Automation (svc-git)    │
│   • GSM Client (gcloud)         │
│   • SSH: 0.0.0.0:22             │
└────────┬────────┬───────────────┘
         │        │
    SSH  │        │ Internal LAN SSH
         ▼        ▼
    ┌────────┐  ┌───────────────────┐
    │ Dev    │  │ Worker Nodes      │
    │ Node   │  │ Node 1, Node 2... │
    └────────┘  └───────────────────┘
```

**Network Requirements:**
- Worker → NAS: SSH 22 (pull IAC)
- NAS → GitHub: HTTPS 443 (push/pull)
- NAS → GCP: gRPC (Secret Manager API)
- Dev → NAS: SSH 22 (push changes during development)

---

## 8. Deployment & Lifecycle Management

### A. **Initial Deployment Checklist**

- [ ] Create GCP service account (`eiq-nas-automation`)
- [ ] Grant `roles/secretmanager.admin` to service account
- [ ] Download service account JSON key
- [ ] Copy key to NAS: `~/.gcp-service-account.json`
- [ ] Run: `bash /home/kushin77/fast-gcp-setup.sh`
- [ ] Add NAS SSH public key to GitHub (deploy key)
- [ ] Test: `sudo -u svc-git ssh -T git@github.com`
- [ ] Test: `sudo -u svc-git -H git -C /home/kushin77 push -u origin main`

### B. **SSH Key Rotation (Zero-Downtime)**

```bash
# 1. Generate new key
sudo -u svc-git ssh-keygen -t ed25519 -f /home/svc-git/.ssh/id_ed25519.new -N ""

# 2. Update GitHub deploy key (API or manual)
NEW_PUB=$(sudo -u svc-git ssh-keygen -y -f /home/svc-git/.ssh/id_ed25519.new)
curl -X POST -H "Authorization: token $GITHUB_TOKEN" \
  -d "{\"title\": \"svc-git NAS\", \"key\": \"$NEW_PUB\", \"read_only\": false}" \
  https://api.github.com/repos/kushin77/eiq-nas/keys

# 3. Update GSM
sudo -u svc-git -H bash gsm-bootstrap.sh nexusshield-prod svc-git-ssh-key

# 4. Activate new key
sudo -u svc-git mv /home/svc-git/.ssh/id_ed25519.new /home/svc-git/.ssh/id_ed25519

# 5. Restart systemd service (triggers fetch from GSM)
sudo systemctl restart svc-git-key.service

# 6. Test
sudo -u svc-git ssh -T git@github.com
```

---

### C. **Boot-Time Recovery**

**Scenario:** NAS reboots, SSH key needs to be fetched from GSM

**Systemd Flow:**
```
Network comes up
  ↓
systemd starts multi-user.target
  ↓
svc-git-key.service (After=network-online.target) triggers
  ↓
fetch-svc-git-key.sh runs (gcloud secrets access...)
  ↓
SSH key written to /home/svc-git/.ssh/id_ed25519
  ↓
svc-git-key.service completes (RemainAfterExit=yes)
  ↓
Other services can now use svc-git for Git operations
```

**Verify:**
```bash
sudo systemctl status svc-git-key.service
sudo journalctl -u svc-git-key.service -n 20
```

---

## 9. Quick Reference: Common Commands

### NAS Administration
```bash
# Check service status
sudo systemctl status svc-git-key.service

# View logs
sudo journalctl -xeu svc-git-key.service -n 50

# Verify SSH key present
sudo -u svc-git test -f /home/svc-git/.ssh/id_ed25519 && echo "✓ Key ready"

# Test GitHub access
sudo -u svc-git ssh -T git@github.com

# Manual GSM bootstrap
cd /home/kushin77/svc-git
bash gsm-bootstrap.sh nexusshield-prod svc-git-ssh-key

# Test Git push (verify everything)
sudo -u svc-git -H git -C /home/kushin77 push -u origin main
```

### Worker Node Integration
```bash
# Configure svc-git user
sudo useradd -r -s /bin/bash svc-git 2>/dev/null || true
sudo mkdir -p /home/svc-git/.ssh && sudo chmod 700 /home/svc-git/.ssh

# Clone NAS repo
sudo -u svc-git git clone git@github.com:kushin77/eiq-nas.git /opt/iac

# Pull latest configs
sudo -u svc-git -H git -C /opt/iac pull origin main

# Apply configuration changes
sudo systemctl reload-or-restart my-service
```

### Dev Node Workflow
```bash
# Clone and configure
git clone git@github.com:kushin77/eiq-nas.git ~/eiq-nas && cd ~/eiq-nas
git config user.email "dev@yourorg" && git config user.name "Developer"

# Push configuration changes
git checkout -b feature/update && git add . && git commit -m "Update config"
git push origin feature/update
# → Create PR → merge to main → worker nodes auto-sync
```

---

## 10. Security & Compliance

### A. **Secret Storage**
- ✅ SSH private keys: Stored in GCP Secret Manager (KMS-encrypted)
- ✅ GitHub PAT: Stored in GCP Secret Manager
- ✅ Runtime SSH key: Fetched at boot, never written to persistent storage
- ✅ Key rotation: 0-downtime via GSM versioning

### B. **Access Control**
- ✅ svc-git user: Login disabled, passwordless SSH only
- ✅ Per-service IAM: GCP service account has only `secretmanager.admin`
- ✅ Audit logging: GCP logs all secret accesses (90-day retention)

### C. **Compliance**
Aligns with project standards: [CREDENTIAL_MANAGEMENT_GSM.md](https://github.com/kushin77/self-hosted-runner#credential-management)

---

## 11. Troubleshooting

### Issue: "gcloud: command not found"
**Solution:** Install Google Cloud SDK
```bash
curl -sSL https://sdk.cloud.google.com | bash
exec -l $SHELL && gcloud init
```

### Issue: "Failed to access secret $SECRET"
**Solution:** Verify service account has `roles/secretmanager.admin`
```bash
gcloud projects get-iam-policy nexusshield-prod \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:eiq-nas-automation@*"
```

### Issue: Systemd service fails to fetch key
**Solution:** Check logs
```bash
sudo journalctl -xeu svc-git-key.service -n 50
# Also verify /etc/default/svc-git-key has PROJECT & SECRET set
sudo cat /etc/default/svc-git-key
```

### Issue: "Permission denied (publickey)"
**Solution:** Add NAS public key to GitHub or backend system
```bash
cat /home/kushin77/svc-git/public_key.txt
# Add to: https://github.com/settings/ssh/new (personal) or repo deploy keys
```

---

## Summary Table

| Component | Purpose | Location | Owner | Access |
|-----------|---------|----------|-------|--------|
| svc-git user | Passwordless Git automation | /home/svc-git | svc-git | SSH key from GSM |
| SSH key | GitHub authentication | /home/svc-git/.ssh/id_ed25519 | svc-git | Fetched at boot |
| GSM secret | Key storage (encrypted) | GCP Secret Manager | gcloud | IAM-controlled |
| Systemd service | Boot-time key fetch | /etc/systemd/system/svc-git-key.service | root | Triggered by network |
| Config | GSM project & secret names | /etc/default/svc-git-key | root | 600 perms |
| Repository | IAC codebase | /home/kushin77 (git clone) | kushin77 | git@github.com:kushin77/eiq-nas.git |

---

**End of Integration Guide**
