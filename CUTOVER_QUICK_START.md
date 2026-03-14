# ⚡ Production Cutover Quick-Start — Operator Guide

**Status:** Ready for immediate execution  
**Timeline:** 1–2 hours (30–60 min canary + monitoring, then full promotion)  
**Risk:** 🟢 LOW (canary with 5-min rollback window)

---

## 🚀 Execute Production Cutover NOW

### Quick Start (1 command)
```bash
export CF_API_TOKEN="<<your-cloudflare-api-token>>"
bash execute-production-cutover.sh
```

**Optional: Add webhooks for notifications**
```bash
export CF_API_TOKEN="<<your-cloudflare-api-token>>"
export SLACK_WEBHOOK_URL="<<your-slack-webhook>>"
export EMAIL_TO="ops-team@nexusshield.io"
bash execute-production-cutover.sh
```

**Optional: Skip monitoring wait (for automated execution)**
```bash
export CF_API_TOKEN="<<your-cloudflare-api-token>>"
export SKIP_MONITORING=1
bash execute-production-cutover.sh
```

---

## 📋 What This Script Does

### Phase 1: DNS Canary (5–30 min)
- Adds low-weight canary A records pointing to 192.168.168.42
- You monitor application for 30–60 minutes
- If errors: script waits for your confirmation before promoting
- If stable: proceed to full promotion

### Phase 2: Full Promotion (immediate)
- Promotes canary records to production
- Updates TTL to 3600s (1 hour) for stability
- Real users now routed to on-prem (192.168.168.42)

### Phase 3: Notifications (automatic if configured)
- Sends Slack message if SLACK_WEBHOOK_URL set
- Sends email if EMAIL_TO set
- Timestamps execution for audit trail

### Phase 4: Validation Instructions
- Displays monitoring dashboard URL (Grafana at 192.168.168.42:3000)
- Shows success criteria (error rate, latency, container health)
- Lists 24-hour post-cutover checklist

---

## ✅ Pre-Execution Checklist

Before running the script:

- [ ] You have a Cloudflare API token (with zone edit permissions)
- [ ] On-call team is standing by (can reach #infra-ops)
- [ ] You're ready to monitor for 30–60 minutes during canary
- [ ] You understand rollback procedure (revert DNS records if needed)
- [ ] You have access to 192.168.168.42 to verify container health
- [ ] Leadership has approved traffic cutover

---

## 🎯 During Canary Phase (30–60 minutes)

**Open these windows in parallel:**

1. **Prometheus/Grafana Dashboard**
   ```
   http://192.168.168.42:3000
   Look for: error rate, latency, container restarts
   ```

2. **Infrastructure SSH (for manual checks)**
   ```bash
   ssh -i ~/.ssh/git-workflow-automation git-workflow-automation@192.168.168.42
   docker-compose -f /home/akushnir/deployments/docker-compose.yml ps  # See containers
   docker-compose logs --tail 50  # Recent logs
   ```

3. **Slack/Email alerts**
   - Monitor #support and #infra-ops for user issues
   - Have escalation contact ready (ops-oncall@nexusshield.io)

**Success criteria to verify:**
- ✅ Error rate < 0.1% (check Prometheus)
- ✅ No container restarts (check docker ps)
- ✅ Database queries <100ms p95 latency
- ✅ Zero user reports in Slack
- ✅ No timeouts or 5xx errors

**If issues occur BEFORE 60 min:**
1. Script will pause and ask for confirmation
2. Press **Ctrl+C** to halt
3. Run rollback (see below)
4. Investigate root cause
5. Re-attempt cutover after fix

---

## 🔄 Rollback Procedure (if needed)

### If issues occur during canary:
```bash
# Script pauses at: "Enter to continue to PHASE 2..."
# Press Ctrl+C to stop

# Then revert DNS manually (quick recovery):
cat dns/backups/cloudflare_*-precutover-records.json | jq '.result[] | select(.type=="A")'
# Copy these IPs and revert in Cloudflare console OR:
# https://dash.cloudflare.com/zones/[zone-id]/dns/records
```

**TTL is 300s (5 min) for canary**, so DNS will propagate back to old IPs within 5 minutes.

### If issues occur AFTER full promotion:
```bash
# DNS will take longer to revert (now at 3600s TTL)
# But same process: revert records, monitor cloud endpoints

# OR keep cloud active in shadow mode:
# Cloud endpoints stay running 48–72 more hours as backup
gcloud run services list --project=nexusshield-prod  # See what can be reverted
```

---

## 📊 Success Indicators

After execution completes:
```
✅ Log file: logs/cutover/execution_<timestamp>.log
✅ DNS records: dns/backups/cloudflare_*-precutover-records.json (backup)
✅ On-prem traffic: Monitor 192.168.168.42:3000 (Grafana)
✅ Cloud endpoints: Still running (shadow mode) or deleted
```

---

## 📞 Escalation

| Issue | Action |
|-------|--------|
| Script fails to run | Check CF_API_TOKEN is set; verify curl available |
| DNS doesn't propagate | Wait 5 min TTL; confirm change-sets executed |
| High error rate during canary | Press Ctrl+C; run rollback; investigate |
| Notification fails | Check SLACK_WEBHOOK_URL / EMAIL_TO; continue anyway |
| Container down on-prem | SSH to 192.168.168.42; check docker-compose logs |

**Emergency contacts:**
- On-call: ops-oncall@nexusshield.io
- Slack: #infra-ops

---

## 🏁 Final Checklist (Post-Execution)

After script completes:

- [ ] DNS records promoted to production (verify with nslookup)
- [ ] On-prem services responding (curl http://nexusshield.io/health)
- [ ] Error rate stable (<0.1%) for 30+ minutes
- [ ] No user-reported issues in Slack
- [ ] Grafana dashboard accessible and updating
- [ ] Notifications sent (if configured)
- [ ] Execution log archived: `logs/cutover/execution_*.log`
- [ ] Rollback procedure reviewed with team
- [ ] 24-hour validation plan confirmed

---

## 🎉 You're Done!

Production traffic is now routed to on-prem (192.168.168.42).

**Next:**
1. Monitor for 24+ hours (dashboards, user reports)
2. Keep cloud endpoints as shadow backup (48–72 hours optional)
3. Rotate any short-lived credentials used during cutover
4. Archive execution logs for compliance
5. Close GitHub issue #2929 (mark as complete)

---

**Script:** `execute-production-cutover.sh`  
**Doc:** This file  
**Status:** 🟢 READY FOR EXECUTION  
**Created:** March 13, 2026
