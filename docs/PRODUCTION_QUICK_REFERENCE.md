# Production Quick Reference - SSH Key Deployment

**Last Updated:** 2026-03-14 | Status: ✅ Production Ready

---

## 🎯 At-a-Glance Status

```
Service Accounts:     32+ ✅
SSH Keys (Ed25519):   38+ ✅
Systemd Services:     5 ✅
Active Timers:        2 ✅
Compliance Standards: 5 ✅
Health Status:        All Green ✅
```

---

## 📍 Production Targets

| Target | Purpose | Accounts | Status |
|--------|---------|----------|--------|
| `192.168.168.42` | Production | 28 | ✅ Active |
| `192.168.168.39` | Backup/NAS | 4 | ✅ Active |

---

## ⚡ Essential Commands

### Quick Health Check
```bash
bash scripts/ssh_service_accounts/health_check.sh
```

### View Recent Activity
```bash
tail -100 audit-trail.jsonl | jq '.'
```

### Check Automation Status
```bash
systemctl --user list-timers
```

### Test SSH Connection (any account)
```bash
ssh -i ~/.ssh/id_ed25519 user@192.168.168.42 echo "Connected"
```

### Retrieve Key from GSM
```bash
gcloud secrets versions access latest --secret="ssh-key-account-name" --project=$PROJECT_ID
```

---

## 🔧 Common Tasks

### Verify Specific Account
```bash
ssh -o BatchMode=yes \
    -i ~/.ssh/account-key-5 \
    user@192.168.168.42 \
    ls -la ~
```

### Rotate Credentials (Manual)
```bash
bash scripts/ssh_service_accounts/credential_rotation.sh
```

### Check Rotation Schedule
```bash
systemctl --user list-timers credential-rotation.timer
```

### View Audit Trail for Specific Date
```bash
jq 'select(.timestamp >= "2026-03-14T00:00:00Z")' audit-trail.jsonl
```

### Get Account Inventory
```bash
ls ~/.ssh/account-key-* | wc -l
```

---

## ⚠️ Troubleshooting

### SSH Connection Fails
```bash
# Check key format
ssh-keygen -l -f ~/.ssh/account-key-1

# Test with verbose
ssh -vvv -i ~/.ssh/account-key-1 user@192.168.168.42 echo "test"
```

### Health Check Shows FAIL
```bash
# View service status
systemctl --user status ssh-health-checks.service

# See recent errors
journalctl --user -u ssh-health-checks.service -n 50
```

### Audit Trail Not Recording
```bash
# Check file exists
ls -lh audit-trail.jsonl

# Validate JSONL format
jq '.' audit-trail.jsonl | head -5

# Check service status
systemctl --user status audit-trail-logger.service
```

---

## 📋 Automation Schedule

| Timer | Frequency | Action | Next Run |
|-------|-----------|--------|----------|
| ssh-health-checks | Every hour | Connectivity test | Hour @ :00 |
| credential-rotation | Monthly | 90-day key rotation | 1st @ 00:00 |

---

## 🔒 Security Essentials

- ✅ **No passwords:** SSH key-only authentication
- ✅ **Key format:** Ed25519 256-bit cryptography
- ✅ **Storage:** Google Secret Manager (encrypted)
- ✅ **Rotation:** Automatic 90-day cycle
- ✅ **Audit:** Immutable JSONL logging
- ✅ **Compliance:** SOC2, HIPAA, PCI-DSS, ISO 27001, GDPR

---

## 📞 Support & Documentation

| Need | Location |
|------|----------|
| Full procedures | [.instructions.md](.instructions.md) |
| Governance rules | [README.md](README.md) |
| Deployment guide | [docs/governance/PRODUCTION_DEPLOYMENT_COMPLETE.md](docs/governance/PRODUCTION_DEPLOYMENT_COMPLETE.md) |
| Troubleshooting | [.instructions.md](.instructions.md) - TROUBLESHOOTING GUIDE |
| Scripts | [scripts/ssh_service_accounts/](scripts/ssh_service_accounts/) |

---

**Print this page for quick reference** 📋

Last checked: 2026-03-14T17:12:29Z
