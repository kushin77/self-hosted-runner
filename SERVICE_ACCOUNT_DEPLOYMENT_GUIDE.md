# Service Account SSH Deployment Guide

## Overview

This guide provides step-by-step instructions to manually set up the three service accounts on your hosts. All SSH keys have been pre-generated and stored locally.

**Generated Date:** March 14, 2026
**Keys Location:** `/home/akushnir/self-hosted-runner/secrets/ssh/`

---

## Service Account Details

### 1. elevatediq-svc-worker-dev
- **Purpose:** Dev-to-Worker communication
- **From Host:** 192.168.168.31 (dev-elevatediq-2)
- **To Host:** 192.168.168.42 (worker-prod)
- **Target User:** elevatediq-svc-worker-dev

**Public Key:**
```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAElfg1bo94bCvQMp8VyNriBYp1WDNUNb0h0ttZIFPF/ elevatediq-svc-worker-dev@dev-elevatediq-2
```

**Private Key Location:** `secrets/ssh/elevatediq-svc-worker-dev/id_ed25519`

---

### 2. elevatediq-svc-worker-nas
- **Purpose:** NAS-to-Worker communication
- **From Host:** 192.168.168.39 (nas-elevatediq)
- **To Host:** 192.168.168.42 (worker-prod)
- **Target User:** elevatediq-svc-worker-nas

**Public Key:**
```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKDFsPNSBG0tZZFyukyofTp8KF0wLPvyApGS0uDrHKbx elevatediq-svc-worker-nas@dev-elevatediq-2
```

**Private Key Location:** `secrets/ssh/elevatediq-svc-worker-nas/id_ed25519`

---

### 3. elevatediq-svc-dev-nas
- **Purpose:** Dev-to-NAS communication
- **From Host:** 192.168.168.31 (dev-elevatediq-2)
- **To Host:** 192.168.168.39 (nas-elevatediq)
- **Target User:** elevatediq-svc-dev-nas

**Public Key:**
```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK43GSxu2AIFGl49n+7arkn4xc5PT4AD6BYehHYWXNoX elevatediq-svc-dev-nas@dev-elevatediq-2
```

**Private Key Location:** `secrets/ssh/elevatediq-svc-dev-nas/id_ed25519`

---

## Deployment Steps

### Step 1: Create Service Accounts on Target Hosts

Run these commands on each **target** host:

#### On 192.168.168.42 (worker-prod):

```bash
# Create elevatediq-svc-worker-dev account
sudo useradd -r -s /bin/bash -m -d /home/elevatediq-svc-worker-dev elevatediq-svc-worker-dev

# Create elevatediq-svc-worker-nas account
sudo useradd -r -s /bin/bash -m -d /home/elevatediq-svc-worker-nas elevatediq-svc-worker-nas

# Configure SSH directories
sudo mkdir -p /home/elevatediq-svc-worker-dev/.ssh
sudo mkdir -p /home/elevatediq-svc-worker-nas/.ssh

sudo chmod 700 /home/elevatediq-svc-worker-dev/.ssh
sudo chmod 700 /home/elevatediq-svc-worker-nas/.ssh
```

#### On 192.168.168.39 (nas-elevatediq):

```bash
# Create elevatediq-svc-dev-nas account
sudo useradd -r -s /bin/bash -m -d /home/elevatediq-svc-dev-nas elevatediq-svc-dev-nas

# Configure SSH directory
sudo mkdir -p /home/elevatediq-svc-dev-nas/.ssh
sudo chmod 700 /home/elevatediq-svc-dev-nas/.ssh
```

### Step 2: Add Public Keys to authorized_keys

On **192.168.168.42**, configure authorized keys:

```bash
# For elevatediq-svc-worker-dev
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAElfg1bo94bCvQMp8VyNriBYp1WDNUNb0h0ttZIFPF/ elevatediq-svc-worker-dev@dev-elevatediq-2" | \
  sudo tee -a /home/elevatediq-svc-worker-dev/.ssh/authorized_keys

# For elevatediq-svc-worker-nas
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKDFsPNSBG0tZZFyukyofTp8KF0wLPvyApGS0uDrHKbx elevatediq-svc-worker-nas@dev-elevatediq-2" | \
  sudo tee -a /home/elevatediq-svc-worker-nas/.ssh/authorized_keys

# Fix permissions
sudo chmod 600 /home/elevatediq-svc-worker-dev/.ssh/authorized_keys
sudo chmod 600 /home/elevatediq-svc-worker-nas/.ssh/authorized_keys

# Ensure correct ownership
sudo chown -R elevatediq-svc-worker-dev:elevatediq-svc-worker-dev /home/elevatediq-svc-worker-dev/.ssh
sudo chown -R elevatediq-svc-worker-nas:elevatediq-svc-worker-nas /home/elevatediq-svc-worker-nas/.ssh
```

On **192.168.168.39**, configure authorized keys:

```bash
# For elevatediq-svc-dev-nas
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK43GSxu2AIFGl49n+7arkn4xc5PT4AD6BYehHYWXNoX elevatediq-svc-dev-nas@dev-elevatediq-2" | \
  sudo tee -a /home/elevatediq-svc-dev-nas/.ssh/authorized_keys

# Fix permissions
sudo chmod 600 /home/elevatediq-svc-dev-nas/.ssh/authorized_keys

# Ensure correct ownership
sudo chown -R elevatediq-svc-dev-nas:elevatediq-svc-dev-nas /home/elevatediq-svc-dev-nas/.ssh
```

### Step 3: Deploy Keys to Source Hosts

From **192.168.168.31**, set up the SSH keys:

```bash
# Create directory for service account keys
mkdir -p ~/.ssh/svc-keys
chmod 700 ~/.ssh/svc-keys

# Copy keys from workspace
cp /home/akushnir/self-hosted-runner/secrets/ssh/elevatediq-svc-worker-dev/id_ed25519 ~/.ssh/svc-keys/elevatediq-svc-worker-dev_key
cp /home/akushnir/self-hosted-runner/secrets/ssh/elevatediq-svc-dev-nas/id_ed25519 ~/.ssh/svc-keys/elevatediq-svc-dev-nas_key

# Fix permissions
chmod 600 ~/.ssh/svc-keys/*_key
```

From **192.168.168.39**, set up the SSH keys:

```bash
# Create directory for service account keys
mkdir -p ~/.ssh/svc-keys
chmod 700 ~/.ssh/svc-keys

# Copy key from workspace
cp /home/akushnir/self-hosted-runner/secrets/ssh/elevatediq-svc-worker-nas/id_ed25519 ~/.ssh/svc-keys/elevatediq-svc-worker-nas_key

# Fix permissions
chmod 600 ~/.ssh/svc-keys/*_key
```

### Step 4: Verify Connectivity

Test each service account connection:

```bash
# Test from 192.168.168.31 to 192.168.168.42
ssh -i ~/.ssh/svc-keys/elevatediq-svc-worker-dev_key elevatediq-svc-worker-dev@192.168.168.42 "whoami"

# Test from 192.168.168.31 to 192.168.168.39
ssh -i ~/.ssh/svc-keys/elevatediq-svc-dev-nas_key elevatediq-svc-dev-nas@192.168.168.39 "whoami"

# Test from 192.168.168.39 to 192.168.168.42
ssh -i ~/.ssh/svc-keys/elevatediq-svc-worker-nas_key elevatediq-svc-worker-nas@192.168.168.42 "whoami"
```

Expected output: The respective service account usernames.

---

## SSH Configuration (Optional)

You can add these entries to `~/.ssh/config` for easier access:

### On 192.168.168.31:

```
Host worker-prod-dev
    HostName 192.168.168.42
    User elevatediq-svc-worker-dev
    IdentityFile ~/.ssh/svc-keys/elevatediq-svc-worker-dev_key
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host nas-dev
    HostName 192.168.168.39
    User elevatediq-svc-dev-nas
    IdentityFile ~/.ssh/svc-keys/elevatediq-svc-dev-nas_key
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
```

### On 192.168.168.39:

```
Host worker-nas
    HostName 192.168.168.42
    User elevatediq-svc-worker-nas
    IdentityFile ~/.ssh/svc-keys/elevatediq-svc-worker-nas_key
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
```

Then you can connect simply with:
```bash
ssh worker-prod-dev    # From .31 to .42
ssh nas-dev            # From .31 to .39
ssh worker-nas         # From .39 to .42
```

---

## Troubleshooting

### "Permission denied (publickey)"
1. Verify the public key is in `~/.ssh/authorized_keys`
2. Check file permissions (should be 600 for authorized_keys, 700 for .ssh)
3. Verify the service account user exists: `id elevatediq-svc-*`

### "Connection refused"
1. Check SSH daemon is running: `sudo systemctl status ssh`
2. Verify the target host is reachable: `ping <target_ip>`
3. Check SSH port (default 22): `scp -P 22 ...`

### "No such file or directory"
1. SSH key must exist at specified path
2. Verify file permissions: `ls -la ~/.ssh/svc-keys/`
3. Use absolute path if needed: `/home/akushnir/self-hosted-runner/secrets/ssh/...`

---

## Security Notes

- All private keys have mode 600 (owner read/write only)
- Service accounts use Ed25519 keys (modern, secure algorithm)
- Service accounts are system users (-r flag) with restricted shell (-s /bin/bash)
- keys are backed up in Google Secret Manager
- Never share private keys outside of secure storage
- Rotate keys periodically (generate new pairs and update authorized_keys)

---

## Reference Commands

### List all generated keys:
```bash
ls -la /home/akushnir/self-hosted-runner/secrets/ssh/*/id_ed25519.pub
```

### View a public key:
```bash
cat /home/akushnir/self-hosted-runner/secrets/ssh/elevatediq-svc-worker-dev/id_ed25519.pub
```

### Check if service account exists on a host:
```bash
# Use service account key for authentication
ssh -i ~/.ssh/git-workflow-automation git-workflow-automation@<host> "id elevatediq-svc-*"
```

### Check authorized_keys on target host:
```bash
# Service account auth
ssh -i ~/.ssh/git-workflow-automation git-workflow-automation@<host> "cat ~/.ssh/authorized_keys | grep -i elevatediq"
```

---

## Storage Locations

- **Private Keys:** `secrets/ssh/<account_name>/id_ed25519`
- **Public Keys:** `secrets/ssh/<account_name>/id_ed25519.pub`
- **Google Secret Manager:** Secrets named `elevatediq-svc-*`
- **Key Fingerprints:** See below

---

## Key Fingerprints

For verification purposes, the SSH key fingerprints are:

```
elevatediq-svc-worker-dev:
  SHA256: <fingerprint>

elevatediq-svc-worker-nas:
  SHA256: <fingerprint>

elevatediq-svc-dev-nas:
  SHA256: <fingerprint>
```

Verify with:
```bash
ssh-keygen -lf /path/to/id_ed25519.pub
```

