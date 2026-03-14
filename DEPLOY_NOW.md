# DEPLOY NOW - Copy & Execute This Command

## ONE-COMMAND PRODUCTION DEPLOYMENT

```bash
cd ~/self-hosted-runner && git pull origin main && ./deploy-nas-monitoring-now.sh
```

---

## WHAT THIS DOES

✅ Validates git state (immutable history)
✅ Checks all deployment files present (5 artifacts)
✅ Verifies SSH access to worker node (192.168.168.42)
✅ Copies scripts and configuration to worker
✅ Executes deployment as root (sudo)
✅ Verifies metrics ingestion (7-phase check)
✅ Tests Prometheus + OAuth access
✅ Shows rollback procedure (if needed)
✅ Displays next steps

**Time: ~2-3 minutes**

---

## DETAILED DEPLOYMENT STEPS (If Advanced)

### Step 1: Prepare
```bash
cd ~/self-hosted-runner
git pull origin main
```

### Step 2: Deploy
```bash
./deploy-nas-monitoring-now.sh
```

### Step 3: Access Prometheus
```
Browser: http://192.168.168.42:4180/prometheus
Login: Google OAuth (required)
```

### Step 4: Verify
```
UI: Status → Targets → Filter 'eiq-nas'
Expected: All 5 jobs showing GREEN ✓
```

---

## ROLLBACK (If Needed)

```bash
ssh elevatediq@192.168.168.42 'sudo ~/deploy-nas-monitoring-direct.sh --rollback'
```

---

## SUCCESS INDICATORS

After deployment:
✅ All 5 scrape jobs GREEN (eiq-nas-node, storage, network, process, custom-metrics)
✅ up{instance="eiq-nas"} = 1.0 (metrics being scraped)
✅ Recording rules available (nas:* prefix queries)
✅ Alerting rules loaded (12+ visible)
✅ Alertmanager connected

---

## STATUS

🟢 **PRODUCTION READY**

All 8 automation mandates satisfied:
✅ Immutable ✅ Ephemeral ✅ Idempotent ✅ No-Ops
✅ Hands-Off ✅ GSM-Ready ✅ No GitHub Actions ✅ OAuth-Exclusive

Deployment approved for immediate execution.

---

**Execute Now:**
```bash
cd ~/self-hosted-runner && git pull origin main && ./deploy-nas-monitoring-now.sh
```
