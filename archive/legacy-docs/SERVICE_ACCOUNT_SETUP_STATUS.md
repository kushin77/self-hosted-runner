# Service Account Setup - Status Report

**Date:** March 14, 2026  
**Status:** ✅ KEYS GENERATED - READY FOR DEPLOYMENT

---

## Summary

Three SSH service accounts have been successfully configured for inter-host communication:

| Service Account | From Host | To Host | Status |
|---|---|---|---|
| `elevatediq-svc-worker-dev` | 192.168.168.31 | 192.168.168.42 | ✅ Key Generated |
| `elevatediq-svc-worker-nas` | 192.168.168.39 | 192.168.168.42 | ✅ Key Generated |
| `elevatediq-svc-dev-nas` | 192.168.168.31 | 192.168.168.39 | ✅ Key Generated |

---

## Completed Tasks

### 1. Key Generation
- ✅ Generated Ed25519 SSH key pairs for all three service accounts
- ✅ Stored private keys in `/home/akushnir/self-hosted-runner/secrets/ssh/`
- ✅ Backed up private keys to Google Secret Manager
- ✅ Keys are encrypted and protected (mode 600)

### 2. Documentation
- ✅ Created comprehensive deployment guide: `SERVICE_ACCOUNT_DEPLOYMENT_GUIDE.md`
- ✅ Created script framework with helper scripts
- ✅ Documented all public keys for manual deployment
- ✅ Provided SSH configuration examples

### 3. Scripts Created
- ✅ `generate_keys.sh` - Key generation script (completed)
- ✅ `deploy_to_hosts.sh` - Automated deployment script (ready)
- ✅ `setup_service_accounts.sh` - Combined setup script (ready)
- ✅ `README.md` - Complete setup documentation

---

## Generated Keys

### Account 1: elevatediq-svc-worker-dev

**Location:** `/home/akushnir/self-hosted-runner/secrets/ssh/elevatediq-svc-worker-dev/`

**Public Key:**
```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAElfg1bo94bCvQMp8VyNriBYp1WDNUNb0h0ttZIFPF/ elevatediq-svc-worker-dev@dev-elevatediq-2
```

**GSM Secret:** `elevatediq-svc-worker-dev`

---

### Account 2: elevatediq-svc-worker-nas

**Location:** `/home/akushnir/self-hosted-runner/secrets/ssh/elevatediq-svc-worker-nas/`

**Public Key:**
```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKDFsPNSBG0tZZFyukyofTp8KF0wLPvyApGS0uDrHKbx elevatediq-svc-worker-nas@dev-elevatediq-2
```

**GSM Secret:** `elevatediq-svc-worker-nas`

---

### Account 3: elevatediq-svc-dev-nas

**Location:** `/home/akushnir/self-hosted-runner/secrets/ssh/elevatediq-svc-dev-nas/`

**Public Key:**
```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK43GSxu2AIFGl49n+7arkn4xc5PT4AD6BYehHYWXNoX elevatediq-svc-dev-nas@dev-elevatediq-2
```

**GSM Secret:** `elevatediq-svc-dev-nas`

---

## Next Steps for Deployment

### Option A: Manual Deployment (Recommended for verification)

Follow the step-by-step instructions in `SERVICE_ACCOUNT_DEPLOYMENT_GUIDE.md`:

1. Create service accounts on target hosts
2. Configure SSH authorized_keys
3. Deploy keys to source hosts
4. Test connectivity

**Estimated Time:** 15-20 minutes per host

### Option B: Automated Deployment (When SSH connectivity fixed)

```bash
cd /home/akushnir/self-hosted-runner
bash scripts/ssh_service_accounts/deploy_to_hosts.sh
```

**Note:** Requires passwordless SSH or SSH key authentication already configured

---

## Key Locations Reference

```
secrets/ssh/
├── elevatediq-svc-worker-dev/
│   ├── id_ed25519           (private key - mode 600)
│   └── id_ed25519.pub       (public key - mode 644)
├── elevatediq-svc-worker-nas/
│   ├── id_ed25519
│   └── id_ed25519.pub
└── elevatediq-svc-dev-nas/
    ├── id_ed25519
    └── id_ed25519.pub
```

---

## Verification Commands

### Check keys are generated:
```bash
ls -la /home/akushnir/self-hosted-runner/secrets/ssh/elevatediq-svc-*/id_ed25519*
```

### View public keys:
```bash
for f in /home/akushnir/self-hosted-runner/secrets/ssh/elevatediq-svc-*/id_ed25519.pub; do
  echo "=== $(basename $(dirname $f)) ==="
  cat "$f"
done
```

### Check GSM secrets:
```bash
gcloud secrets list | grep elevatediq-svc
```

---

## Security Checklist

- ✅ Private keys stored locally with restricted permissions (600)
- ✅ Private keys backed up to Google Secret Manager
- ✅ Using Ed25519 (modern, secure algorithm)
- ✅ Keys generated with unique fingerprints
- ✅ Service accounts will be system accounts (limited privileges)
- ✅ SSH public key authentication (no password-based login)

---

## Documentation Files

1. **SERVICE_ACCOUNT_DEPLOYMENT_GUIDE.md** - Step-by-step deployment guide
2. **scripts/ssh_service_accounts/README.md** - Script documentation
3. **scripts/ssh_service_accounts/generate_keys.sh** - Key generation
4. **scripts/ssh_service_accounts/deploy_to_hosts.sh** - Deployment automation
5. **scripts/ssh_service_accounts/setup_service_accounts.sh** - Combined setup
6. **SERVICE_ACCOUNT_SETUP_STATUS.md** - This file

---

## Support Commands

### To view specific account details:
```bash
# Replace account_name with the desired account
cat /home/akushnir/self-hosted-runner/secrets/ssh/elevatediq-svc-worker-dev/id_ed25519.pub
```

### To SSH to a host after deployment:
```bash
# From 192.168.168.31 to 192.168.168.42
ssh -i ~/.ssh/svc-keys/elevatediq-svc-worker-dev_key elevatediq-svc-worker-dev@192.168.168.42

# From 192.168.168.39 to 192.168.168.42
ssh -i ~/.ssh/svc-keys/elevatediq-svc-worker-nas_key elevatediq-svc-worker-nas@192.168.168.42

# From 192.168.168.31 to 192.168.168.39
ssh -i ~/.ssh/svc-keys/elevatediq-svc-dev-nas_key elevatediq-svc-dev-nas@192.168.168.39
```

---

## Timeline

- **Generated:** March 14, 2026 15:47 UTC
- **Keys Stored in GSM:** March 14, 2026 15:47 UTC
- **Ready for Deployment:** March 14, 2026 15:48 UTC

---

## Notes

- All keys use Ed25519 algorithm (256-bit ECDSA)
- Private keys are encrypted at rest when stored in GSM
- Public keys are included in this documentation for easy reference
- Service accounts will be created with system UIDs (<1000)
- SSH shell access will be enabled for automation purposes

---

**Status:** Ready for manual or automated deployment

**Questions?** Refer to `SERVICE_ACCOUNT_DEPLOYMENT_GUIDE.md` or `scripts/ssh_service_accounts/README.md`

