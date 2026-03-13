# 🔑 Operator Token Retrieval & Execution Guide

**Date:** March 13, 2026  
**Status:** Ready for immediate execution (CF_API_TOKEN required)  
**Time to Deploy:** ~2 hours (including canary monitoring)

---

## 📋 Prerequisites & Current State

All autonomous preparation is **100% complete**:
- ✅ DNS cutover scripts ready
- ✅ Production orchestration script ready
- ✅ Documentation complete  
- ✅ Governance verified
- ✅ git history clean

**Blocking item:** `CF_API_TOKEN` (Cloudflare API token with Zone Edit permissions)

---

## 🔓 Step 1: Retrieve CF_API_TOKEN from Google  Secret Manager

The Cloudflare API token is stored in the nexusshield-prod GCP project under `Secret Manager > cloudflare-api-token`.

### Option A: Direct Web Console (Recommended for Operators)

1. Open [Google Cloud Console - Secret Manager](https://console.cloud.google.com/security/secret-manager)
2. Ensure you're in the **nexusshield-prod** project
3. Click **cloudflare-api-token** 
4. Click **Versions** tab
5. Click **REVEAL SECRET** on the latest version
6. Copy the token value

### Option B: gcloud CLI (For Automation/CI/CD)

**Requires:** Active gcloud authentication to nexusshield-prod project
```bash
# Authenticate if not already done
gcloud auth login
gcloud config set project nexusshield-prod

# Retrieve the secret
CF_API_TOKEN=$(gcloud secrets versions access latest --secret=cloudflare-api-token)
echo "Token retrieved: ${CF_API_TOKEN:0:10}...***"
```

### Option C: Via Service Account Key (For Sealed CI/CD)

If you have a nexusshield-prod service account JSON key file:
```bash
gcloud auth activate-service-account --key-file=/path/to/service-account-key.json
gcloud config set project nexusshield-prod
CF_API_TOKEN=$(gcloud secrets versions access latest --secret=cloudflare-api-token)
```

---

## 🚀 Step 2:  Execute Production DNS Cutover

Once you have the token, execute the production cutover script:

```bash
cd /home/akushnir/self-hosted-runner

# Set the Cloudflare API token
export CF_API_TOKEN="<paste-token-here>"

# Optional: Enable Slack notifications (get from GSM: slack-webhook)
export SLACK_WEBHOOK_URL="$(gcloud secrets versions access latest --secret=slack-webhook --project=nexusshield-prod)"

# Execute the full 4-phase production cutover
bash execute-production-cutover.sh
```

---

## 📊 What Happens Next (Automatic)

### Phase 1: DNS Canary (5 min setup + 30–60 min monitoring)
- Script makes initial Cloudflare API calls to set TTL=300s
- Script **pauses** here and prompts: **"Press Enter to continue to PHASE 2"**
- **Your Job:** Monitor the Grafana dashboard at `http://192.168.168.42:3000`
  - Watch for error rate: Should stay **<0.1%** 
  - Watch for latency: Should be **normal** (check baseline)
  - Watch for containers: All **13/13 should be running**
  - Wait **30–60 minutes** for canary stability validation
- Once confident, press **Enter** to proceed

### Phase 2: Full Promotion (2 min, automatic)
- Script raises DNS TTL to 3600s
- Script updates all DNS records to point to on-prem (192.168.168.42)
- All traffic now flows through on-prem infrastructure
- **No manual intervention needed**

### Phase 3: Notifications (< 1 min, automatic)
- Script sends Slack notification (if webhook URL provided)
- Script sends optional email notifications
- All stakeholders informed of cutover completion

### Phase 4: Validation Instructions (auto-displayed)
- Script displays **24-hour post-cutover monitoring checklist**
- Operator follows checklist for error rate, latency, container health  
- Everything should return to normal operation

---

## ✅ Success Criteria

**Cutover is successful when:**
- Phase 1 canary monitoring shows **<0.1% error rate** for 30+ minutes
- Phase 2 completes without errors
- All DNS records show **192.168.168.42** as target
- Grafana dashboard shows all 13 containers **running**
- Slack/email notifications delivered  
- Post-cutover monitoring shows **normal operations**

---

## 🔄 Quick Command Reference

```bash
# Prepare environment
export CF_API_TOKEN="<from-gsm-cloudflare-api-token>"

# Optional Slack notifications
export SLACK_WEBHOOK_URL="$(gcloud secrets versions access latest --secret=slack-webhook --project=nexusshield-prod 2>/dev/null || echo '')"

# Execute cutover
cd /home/akushnir/self-hosted-runner
bash execute-production-cutover.sh

# If you want full automation (skip Phase 1 monitoring pause):
export SKIP_MONITORING=1
bash execute-production-cutover.sh
```

---

## 🚨 If Something Goes Wrong

### Canary Phase Fails (high error rate >0.1%)
1. **DON'T press Enter** to proceed to Phase 2
2. Script can be stopped: `Ctrl+C`
3. Execute rollback: `bash scripts/dns/execute-dns-cutover.sh cloudflare nexusshield.io --mode ROLLBACK`
4. DNS records revert to cloud routing

### Phase 2 Fails (script errors during promotion)
1. Cutover is partially applied (DNS  may be inconsistent)
2. **Immediate action:** Check Cloudflare console for uncommitted changes
3. Rollback via Cloudflare console: Revert to previous DNS state
4. Run: `bash execute-production-cutover.sh --rollback`

### Full Rollback to Cloud
```bash
# If cutover failed and you need to revert to cloud:
cd /home/akushnir/self-hosted-runner
CF_API_TOKEN="<token>" bash scripts/dns/execute-dns-cutover.sh cloudflare nexusshield.io --mode ROLLBACK
```

---

## 📞 Support & Escalation

| Issue | Responsible | Contact |
|-------|-------------|---------|
| Cloudflare token not found | GCP Admin | Check nexusshield-prod project, Secret Manager, cloudflare-api-token |
| DNS resolution still pointing to cloud | DNS/Network | Check Cloudflare DNS console, verify TTL propagation (~300s) |
| On-prem containers not responding | Infrastructure | Check container status: `docker ps -a` on 192.168.168.42 |
| Monitoring anomalies | SRE | Check Prometheus/Grafana, review application logs |

---

## 📝 Execution Checklist

Before executing:
- [ ] CF_API_TOKEN retrieved from GSM and validated
- [ ] On-prem infrastructure (192.168.168.42) running and verified
- [ ] Slack webhook URL optional but prepared (if notifications desired)
- [ ] Team notified of cutover timing
- [ ] Monitoring (Grafana) dashboard open in separate terminal/window

During execution:
- [ ] Phase 1 canary DNS setup completes (5 min)
- [ ] Phase 1 monitoring shows stable error rate for 30+ min
- [ ] Press Enter to continue to Phase 2
- [ ] Phase 2 full promotion completes (2 min)
- [ ] Phase 3 notifications delivered (if configured)
- [ ] Phase 4 validation instructions displayed

After execution:
- [ ] DNS resolution confirms 192.168.168.42
- [ ] User traffic flows through on-prem
- [ ] Monitoring dashboard shows normal operations
- [ ] 24-hour post-cutover validation running
- [ ] Team notified of successful completion

---

## 🎯 Timeline Summary

| Phase | Duration | Owner | Blocker? |
|-------|----------|-------|----------|
| Retrieve CF_API_TOKEN | 2–5 min | You | **YES** |
| Phase 1 canary DNS | 5 min + 30–60 min monitoring | Script + You | NO |
| Phase 2 full promotion | 2 min | Script | NO |
| Phase 3 notifications | <1 min | Script | NO |
| Phase 4 validation | 24+ hours | You (passive) | NO |
| **Total Active Time** | **~2 hours** | | |

---

## ✨ Final Checklist

```
✅ DNS cutover script created: scripts/dns/execute-dns-cutover.sh
✅ Production orchestration ready: execute-production-cutover.sh
✅ Documentation complete: 4 guides
✅ Governance verified: 8/8 requirements
✅ Git history clean: Latest commit 74385c625

🔴 **BLOCKING:** CF_API_TOKEN must be retrieved from GSM
🔴 **ACTION REQUIRED:** Follow Step 1 above to retrieve token
🟢 **THEN:** Execute `bash execute-production-cutover.sh` with token

**Status:** 🟢 PRODUCTION READY FOR CUTOVER (operator action needed)
```

---

Generated: March 13, 2026  
Project: nexusshield  
Prepared by: Infrastructure Automation System
