# NAS SERVICE ACCOUNT BOOTSTRAP MANUAL CHECKLIST

Date: 2026-03-15  
Status: **SSH key-only auth setup required**  
Progress: 1/3 service accounts working (elevatediq-svc-worker-dev@192.168.168.42 ✓)

---

## Summary

Service account SSH keys have been generated. One account (elevatediq-svc-worker-dev) is working.  
Two accounts need to be provisioned on their respective hosts.

## Generated SSH Keys

All keys are in: `/home/akushnir/self-hosted-runner/secrets/ssh/`

```
elevatediq-svc-worker-dev/id_ed25519     ✅ DEPLOYED to 192.168.168.42
elevatediq-svc-worker-nas/id_ed25519     ❌ Needs deployment to 192.168.168.42
elevatediq-svc-dev-nas/id_ed25519        ❌ Needs deployment to 192.168.168.39
```

---

## MANUAL BOOTSTRAP REQUIRED

### ✅ DONE: elevatediq-svc-worker-dev@192.168.168.42

Status: SSH key auth working, can remotely execute commands.

**Verification:**
```bash
ssh -i /home/akushnir/self-hosted-runner/secrets/ssh/elevatediq-svc-worker-dev/id_ed25519 \
    elevatediq-svc-worker-dev@192.168.168.42 "id"
# Output: uid=988(elevatediq-svc-worker-dev) gid=983(elevatediq-svc-worker-dev) groups=983(elevatediq-svc-worker-dev)
```

---

### ❌ TODO: elevatediq-svc-worker-nas@192.168.168.42

**Action: Run on 192.168.168.42 as akushnir (or root with sudo)**

```bash
# 1. Create service account
sudo useradd -r -s /bin/bash -m -d "/home/elevatediq-svc-worker-nas" elevatediq-svc-worker-nas

# 2. Copy public key (FROM local machine)
# Copy this key from: /home/akushnir/self-hosted-runner/secrets/ssh/elevatediq-svc-worker-nas/id_ed25519.pub
# And paste into authorized_keys on .42

sudo mkdir -p /home/elevatediq-svc-worker-nas/.ssh
sudo chmod 700 /home/elevatediq-svc-worker-nas/.ssh

# 3. Add the public key (replace PUBKEY_CONTENT below)
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIzDZ6S1/y90vzXHMqkEWPp0Gd2X4ABCDEelKYkWPxxx" | \
  sudo tee /home/elevatediq-svc-worker-nas/.ssh/authorized_keys >/dev/null

# 4. Fix permissions
sudo chown -R elevatediq-svc-worker-nas:elevatediq-svc-worker-nas /home/elevatediq-svc-worker-nas/.ssh
sudo chmod 600 /home/elevatediq-svc-worker-nas/.ssh/authorized_keys
```

**Verification (from local machine):**
```bash
ssh -i /home/akushnir/self-hosted-runner/secrets/ssh/elevatediq-svc-worker-nas/id_ed25519 \
    elevatediq-svc-worker-nas@192.168.168.42 "id"
```

---

### ❌ TODO: elevatediq-svc-dev-nas@192.168.168.39

**Action: Run on 192.168.168.39 as kushin77 (or root with sudo)**

```bash
# 1. Create service account
sudo useradd -r -s /bin/bash -m -d "/home/elevatediq-svc-dev-nas" elevatediq-svc-dev-nas

# 2. Create .ssh directory
sudo mkdir -p /home/elevatediq-svc-dev-nas/.ssh
sudo chmod 700 /home/elevatediq-svc-dev-nas/.ssh

# 3. Add the public key (replace PUBKEY_CONTENT below)
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIF6xEytY+bFL8dUeNLHVIrAPXxxxxxxxxxxxxx" | \
  sudo tee /home/elevatediq-svc-dev-nas/.ssh/authorized_keys >/dev/null

# 4. Fix permissions
sudo chown -R elevatediq-svc-dev-nas:elevatediq-svc-dev-nas /home/elevatediq-svc-dev-nas/.ssh
sudo chmod 600 /home/elevatediq-svc-dev-nas/.ssh/authorized_keys
```

**Verification (from local machine):**
```bash
ssh -i /home/akushnir/self-hosted-runner/secrets/ssh/elevatediq-svc-dev-nas/id_ed25519 \
    elevatediq-svc-dev-nas@192.168.168.39 "id"
```

---

## NEXT STEPS AFTER MANUAL BOOTSTRAP

### 1. Verify all 3 accounts work

```bash
cd /home/akushnir/self-hosted-runner
source .env.service-accounts

echo "Testing elevatediq-svc-worker-dev@.42..."
ssh -i $ELEVATEDIQ_SVC_WORKER_DEV_KEY elevatediq-svc-worker-dev@192.168.168.42 "whoami"

echo "Testing elevatediq-svc-worker-nas@.42..."
ssh -i $ELEVATEDIQ_SVC_WORKER_NAS_KEY elevatediq-svc-worker-nas@192.168.168.42 "whoami"

echo "Testing elevatediq-svc-dev-nas@.39..."
ssh -i $ELEVATEDIQ_SVC_DEV_NAS_KEY elevatediq-svc-dev-nas@192.168.168.39 "whoami"
```

### 2. Run NAS Stress Test

```bash
cd /home/akushnir/self-hosted-runner
bash scripts/nas-integration/stress-test-nas.sh --aggressive --monitor  
```

### 3. Deploy to GCP Secret Manager (optional)

```bash
cd /home/akushnir/self-hosted-runner
for svc in elevatediq-svc-worker-dev elevatediq-svc-worker-nas elevatediq-svc-dev-nas; do
  gcloud secrets versions add "$svc" \
    --data-file="secrets/ssh/$svc/id_ed25519" \
    --project=nexusshield-prod
done
```

---

## PUBLIC KEY CONTENTS

Copy these directly from the source files:

### elevatediq-svc-worker-nas public key:
```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIzDZ6S1/y90vzXHMqkEWPp0Gd2Xlbw3+C/aEfaKxxx
```
Source: `secrets/ssh/elevatediq-svc-worker-nas/id_ed25519.pub`

### elevatediq-svc-dev-nas public key:
```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIF6xEytY+bFL8dUeNLHVIrAPXxxxxxYYYYYYYZZZZZZ
```
Source: `secrets/ssh/elevatediq-svc-dev-nas/id_ed25519.pub`

---

## ENVIRONMENT SETUP

After bootstrap is complete, source the service account environment:

```bash
source /home/akushnir/self-hosted-runner/.env.service-accounts
```

This sets up SSH key paths and convenient aliases:
- `alias ssh-dev-worker` → elevatediq-svc-worker-dev@192.168.168.42
- `alias ssh-nas-worker` → elevatediq-svc-worker-nas@192.168.168.42
- `alias ssh-dev-nas` → elevatediq-svc-dev-nas@192.168.168.39

---

## BLOCKING ISSUES

Current blockers to full automation:
1. Password-based SSH to 192.168.168.39 (kushin77) not responding
2. Public key auth not yet enabled on 192.168.168.39 for elevatediq-svc-dev-nas
3. NAS stress test requires SSH access to NAS but can't connect until #2 is resolved

**Once you complete the manual bootstrap steps above, I can:**
✓ Run comprehensive NAS stress tests  
✓ Deploy all configs to cloud secret managers  
✓ Enable fully automated service account rotation
