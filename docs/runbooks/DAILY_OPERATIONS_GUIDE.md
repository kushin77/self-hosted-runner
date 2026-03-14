# Day-to-Day Operations Runbook - SSH Key Deployment

**Status:** 🟢 Production Operational | Last Updated: 2026-03-14  
**Target Audience:** System Operators, DevOps Engineers, Infrastructure Teams

---

## Morning Startup Checklist (Daily)

```bash
#!/bin/bash
# Daily health verification - run at start of business day

echo "=== Daily Startup Checks ==="

# 1. Verify systemd services are running
echo "✓ Checking systemd services..."
systemctl --user list-units --type service --state running | grep -E "(ssh-health|credential-rotation|audit-trail|automation|compliance)" || echo "WARNING: Services not found"

# 2. Quick health check
echo "✓ Running health check..."
bash scripts/ssh_service_accounts/health_check.sh | tail -10

# 3. Check audit trail
echo "✓ Recent audit entries..."
tail -5 audit-trail.jsonl | jq '.action, .status, .timestamp'

# 4. Verify no failed timers
echo "✓ Active timers..."
systemctl --user list-timers
```

---

## Hourly Monitoring (Automated)

**These happen automatically - no action needed:**

- ✅ SSH health checks run every hour
- ✅ Results logged to audit trail
- ✅ Failed accounts trigger alerts
- ✅ Auto-retry logic engages on failure

**Command to verify automated runs:**
```bash
journalctl --user -u ssh-health-checks.service --no-pager | tail -20
```

---

## Weekly Maintenance (Every Monday)

### 1. Validate All Accounts (30 minutes)
```bash
#!/bin/bash
# Comprehensive account validation

echo "=== Weekly Account Validation ==="
for i in {1..32}; do
  echo -n "Account $i: "
  ssh -o BatchMode=yes \
      -o ConnectTimeout=3 \
      -i ~/.ssh/account-key-$i \
      user@192.168.168.42 \
      'echo $HOSTNAME' 2>/dev/null && echo "✅ OK" || echo "❌ FAIL"
done
```

### 2. Review Audit Trail for Anomalies
```bash
# Check for failed operations
jq 'select(.status == "failed")' audit-trail.jsonl | wc -l

# Check for unusual activity
jq 'select(.timestamp >= "2026-03-07T00:00:00Z")' audit-trail.jsonl | jq -r '.action' | sort | uniq -c
```

### 3. Check Disk Usage
```bash
# Audit trail file size
du -h audit-trail.jsonl

# Key storage
du -h ~/.ssh/

# Total project size
du -sh ~/self-hosted-runner
```

### 4. Verify Backup Status
```bash
# Backup keys to secure location
tar czf backup-keys-$(date +%Y-%m-%d).tar.gz ~/.ssh/account-key-*
ls -lh backup-keys-*.tar.gz | head -5
```

---

## Monthly Maintenance (1st of Month)

### 1. Credential Rotation Day
**Time:** First day of month at 00:00 UTC (automated)

**Automated Actions:**
- Systemd timer triggers automatically
- Old keys rotated out
- New keys generated and stored in GSM
- Health checks verify all accounts still accessible
- Audit trail records rotation event

**Manual Monitoring:**
```bash
# Watch rotation in progress
journalctl --user -u credential-rotation.service -f

# Verify rotation completed
jq 'select(.action == "rotation")' audit-trail.jsonl | tail -10
```

### 2. Compliance Audit
```bash
# Export audit trail for compliance team
jq -r '[.timestamp, .action, .status, .account] | @csv' audit-trail.jsonl > audit-export-$(date +%Y-%m).csv

# Verify all compliance standards active
bash scripts/final_validation_certification.sh | grep -i "compliance"
```

### 3. Update Documentation
```bash
# Export current metrics for documentation
cat > deployment-metrics-$(date +%Y-%m).md << 'EOF'
# Deployment Metrics - $(date +%Y-%m)

- Active Accounts: $(grep -c '"action": "deployment"' audit-trail.jsonl)
- Key Rotations: $(jq 'select(.action == "rotation")' audit-trail.jsonl | wc -l)
- Failed Checks: $(jq 'select(.status == "failed")' audit-trail.jsonl | wc -l)
- Availability: $(echo "scale=2; 100 - ($(jq 'select(.status == "failed")' audit-trail.jsonl | wc -l) * 100 / $(jq 'select(.action == "health_check")' audit-trail.jsonl | wc -l))" | bc)%
EOF
```

### 4. Quarterly Review (Every 3 Months)

**At month 3, 6, 9, 12:**

```bash
# Full compliance verification
bash scripts/final_validation_certification.sh

# Archive quarterly report
jq 'select(.timestamp >= "'"$(date --date='3 months ago' +%Y-%m-%d)"'T00:00:00Z")' audit-trail.jsonl > docs/archive/quarterly-audit-$(date +%Y-Q$(( ($(date +%m)-1)/3+1 ))).jsonl

# Update certification
echo "Last reviewed: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> PRODUCTION_DEPLOYMENT_COMPLETE.md
```

---

## Incident Response

### Alert: SSH Connection Failed
**When:** Health check alerts you about connection failure

**Response Steps:**
```bash
# 1. Identify which account failed
systemctl --user status ssh-health-checks.service

# 2. Test manually
ssh -vvv -i ~/.ssh/account-key-X user@192.168.168.42 echo test

# 3. Check target host
ping 192.168.168.42

# 4. Verify key exists and has correct permissions
ls -la ~/.ssh/account-key-X
# Should be -rw------- (600)

# 5. If key file missing, restore from GSM
gcloud secrets versions access latest --secret="ssh-key-account-X" --project=$PROJECT_ID > ~/.ssh/account-key-X
chmod 600 ~/.ssh/account-key-X

# 6. Re-run health check
bash scripts/ssh_service_accounts/health_check.sh
```

### Alert: Rotation Failed
**When:** Monthly rotation doesn't complete

**Response Steps:**
```bash
# 1. Check rotation service status
systemctl --user status credential-rotation.service

# 2. View error logs
journalctl --user -u credential-rotation.service -n 100

# 3. Dry-run to diagnose
bash scripts/ssh_service_accounts/credential_rotation.sh --dry-run

# 4. Manual rotation (if needed)
bash scripts/ssh_service_accounts/credential_rotation.sh --force

# 5. Verify all accounts still accessible
bash scripts/ssh_service_accounts/health_check.sh

# 6. Log incident
echo '{"timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'", "action": "rotation_manual", "status": "incident_response"}' >> audit-trail.jsonl
```

### Alert: Multiple Accounts Unreachable
**When:** Health checks show >25% failure rate

**Escalation:**
```bash
# 1. Get full picture
bash scripts/ssh_service_accounts/health_check.sh

# 2. Check if target host is offline
ping -c 3 192.168.168.42

# 3. If connectivity issue, check network
traceroute 192.168.168.42

# 4. If host is down, fail over to backup
# Update connections to use 192.168.168.39 instead
ping 192.168.168.39

# 5. Document incident
echo '{"timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'", "action": "failover", "status": "incident_escalation", "target": "192.168.168.39"}' >> audit-trail.jsonl

# 6. Notify operations team
# Send incident notification (email/Slack)
```

---

## Regular Reports

### Weekly Report
```bash
#!/bin/bash
# Weekly operations summary

WEEK=$(date +%Y-W%V)
echo "# Operations Report - Week $WEEK" > reports/weekly-$WEEK.md
echo "" >> reports/weekly-$WEEK.md
echo "**Period:** $(date -d '1 week ago' +%Y-%m-%d) to $(date +%Y-%m-%d)" >> reports/weekly-$WEEK.md
echo "" >> reports/weekly-$WEEK.md

echo "## Health Status" >> reports/weekly-$WEEK.md
bash scripts/ssh_service_accounts/health_check.sh >> reports/weekly-$WEEK.md

echo "" >> reports/weekly-$WEEK.md
echo "## Recent Activities" >> reports/weekly-$WEEK.md
jq '.action' audit-trail.jsonl | sort | uniq -c >> reports/weekly-$WEEK.md
```

### Monthly Report
```bash
#!/bin/bash
# Monthly operations summary

MONTH=$(date +%Y-%m)
echo "# Operations Report - $MONTH" > reports/monthly-$MONTH.md

# Add metrics
jq -r '[.timestamp, .action, .status] | @csv' audit-trail.jsonl >> reports/monthly-$MONTH.md

# Add compliance status
bash scripts/final_validation_certification.sh >> reports/monthly-$MONTH.md
```

---

## Useful Queries

### Find all failed operations
```bash
jq 'select(.status == "failed")' audit-trail.jsonl
```

### Find all rotations
```bash
jq 'select(.action == "rotation")' audit-trail.jsonl
```

### Find activity by account
```bash
jq 'select(.account == "account-name")' audit-trail.jsonl
```

### Find events in date range
```bash
jq 'select(.timestamp >= "2026-03-01T00:00:00Z" and .timestamp <= "2026-03-14T23:59:59Z")' audit-trail.jsonl
```

### Generate statistics
```bash
# Count events by action
jq '.action' audit-trail.jsonl | sort | uniq -c

# Count events by status
jq '.status' audit-trail.jsonl | sort | uniq -c

# Average daily activity
echo "$(jq '.action' audit-trail.jsonl | wc -l) events in $(jq '.timestamp' audit-trail.jsonl | head -1 | wc -l) days"
```

---

## Emergency Procedures

### Complete System Restart
```bash
# 1. Stop all services
systemctl --user stop ssh-health-checks.service
systemctl --user stop credential-rotation.service
systemctl --user stop audit-trail-logger.service
systemctl --user stop automation-orchestrator.service
systemctl --user stop compliance-monitor.service

# 2. Stop all timers
systemctl --user stop ssh-health-checks.timer
systemctl --user stop credential-rotation.timer

# 3. Verify stopped
systemctl --user list-units --type service --state running

# 4. Restart all services
systemctl --user start ssh-health-checks.service
systemctl --user start credential-rotation.service
systemctl --user start audit-trail-logger.service
systemctl --user start automation-orchestrator.service
systemctl --user start compliance-monitor.service

# 5. Restart timers
systemctl --user start ssh-health-checks.timer
systemctl --user start credential-rotation.timer

# 6. Verify operational
systemctl --user list-timers
```

### Key Recovery from GSM
```bash
# If all local keys are lost
mkdir -p ~/.ssh-recovery

for SECRET in $(gcloud secrets list --project=$PROJECT_ID --filter="labels.type:ssh-key" --format="value(name)"); do
  gcloud secrets versions access latest --secret="$SECRET" --project=$PROJECT_ID > ~/.ssh-recovery/$SECRET
  chmod 600 ~/.ssh-recovery/$SECRET
done

# Verify recovered
ls -la ~/.ssh-recovery/
```

---

## Quick Reference Commands

| Task | Command |
|------|---------|
| Check health | `bash scripts/ssh_service_accounts/health_check.sh` |
| View audit log | `tail -50 audit-trail.jsonl \| jq '.'` |
| List timers | `systemctl --user list-timers` |
| Manual rotation | `bash scripts/ssh_service_accounts/credential_rotation.sh` |
| Verify compliance | `bash scripts/final_validation_certification.sh` |
| Test account | `ssh -i ~/.ssh/account-key-1 user@192.168.168.42 echo test` |
| Generate report | `jq '.' audit-trail.jsonl > report-$(date +%Y-%m-%d).json` |

---

**Last Updated:** 2026-03-14 | **Version:** 1.0 | **Status:** Production Ready
