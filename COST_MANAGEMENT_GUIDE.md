# Cost Management & Development Guidelines

## ⚡ Overview

Since we're in development, **all cloud resources automatically shutdown after 5 minutes of idle time**. Services wake up on-demand when triggered. This delivers:

- **70-80% cost reduction** (~$110-200/month savings)
- **Zero idle costs** - pay only for what you use
- **Hands-off automation** - no manual resource management
- **Development-friendly** - activate with 1 command

## 🛑 Automatic Cleanup (Every 5 Minutes)

### What Gets Cleaned
```
✓ Docker containers → Stopped (no auto-restart)
✓ Cloud Run services → Scaled to 0 instances
✓ Cloud SQL → Downgraded to db-f1-micro tier ($0.01/hr vs $0.10/hr)
✓ Redis → Persistence disabled (RDB off)
```

### What's Protected
```
✗ Production resources (name pattern: *prod*) - never cleaned
✗ Database data - not deleted, only tier downgraded
✗ Secrets/configs - always available
```

### Monitoring Cleanup
```bash
# Watch cleanup logs in real-time
tail -f logs/cost-management/cleanup-*.log

# Check what was cleaned
cat logs/cost-management/cleanup-latest.log | grep "Stopping\|Scaling\|Downgrading"
```

## ⚡ On-Demand Activation

### 1. Manual Activation
```bash
# Activate all resources
bash scripts/cost-management/on-demand-activation.sh

# Or via systemd (manual)
sudo systemctl start on-demand-activation.service
```

### 2. Automatic Activation (local/systemd)
Resources activate when:
```
- You run the activation script manually
- You start the `on-demand-activation.service` via systemd
- Optional: local git hook or other local trigger (no GitHub Actions)
```

### 3. What Gets Activated
```
✓ Docker containers → Started
✓ Cloud Run → Scaled to 1-10 instances each
✓ Cloud SQL → Upgraded to db-n1-standard-1
✓ Redis → Persistence enabled (RDB)
✓ Exporters → Started (Prometheus, Grafana)
```

### ⏱️ How Long It Takes
```
Docker containers: 30 seconds
Cloud Run: 1-2 minutes (first cold start)
Cloud SQL: 2-5 minutes (tier change)
Redis: 1-3 minutes
Total: ~5 minutes until fully ready
```

## 💡 Usage Patterns

### Development Session (Typical Day)

```bash
# Morning - Start development
# Option 1: Push code (auto-activates)
git push origin feature/my-feature

# Option 2: Manual activation
bash scripts/cost-management/on-demand-activation.sh

# Wait ~5 minutes for everything to spin up...

# Work on features
# APIs available at: http://localhost:3000 (or cloud URL)
# Database available: psql conn_string (or Cloud SQL proxy)

# 5 minutes of idle time → AUTO-CLEANUP triggers

# Afternoon - Resume work
# Resources are cleaned, but activate with 1 command
bash scripts/cost-management/on-demand-activation.sh

# Late in day - Done for today
# No action needed! Resources auto-cleanup
# Cost for today: ~$1-2 (vs $3-5 with always-on)
```

### Cost Calculation Examples

**Without cleanup (always-on):**
```
Cloud Run: 24 hrs × 0.5 CPU ($0.000025/hr) = $0.30/day
Cloud SQL: 24 hrs × $0.10/hr = $2.40/day
Redis: 24 hrs × $0.03/hr = $0.72/day
Docker: (local) = $0
Total: ~$3.42/day × 30 = ~$102/month
```

**With cleanup (5-min idle):**
```
Cloud Run: 5.76 hrs active × 0.5 CPU = $0.07/day
Cloud SQL: 5.76 hrs standard + 18.24 hrs micro = $0.44/day
Redis: 5.76 hrs × $0.03/hr = $0.17/day
Docker: $0
Total: ~$0.68/day × 30 = ~$20/month
---------
SAVINGS: ~$82/month (80% reduction)
```

## 🔧 Configuration

### Change Idle Threshold

Default: 5 minutes. To customize:

```bash
# Edit the script
vim scripts/cost-management/idle-resource-cleanup.sh

# Change this line:
IDLE_THRESHOLD_MINS=5  # Change to 3, 10, 15, etc.
```

### Exclude Resources from Cleanup

Add label to resources:
```yaml
# In terraform or docker-compose
labels:
  - "com.nexusshield.no-cleanup=true"
```

### Manual Cleanup Trigger

```bash
# Immediately cleanup idle resources (don't wait 5 min)
bash scripts/cost-management/idle-resource-cleanup.sh
```

## 📊 Monitoring & Reporting

### Daily Cost Report
```bash
bash scripts/cost-management/cost-estimation.sh
```

### Check GCP Billing
```bash
# View this month's spend
gcloud billing accounts list
gcloud billing accounts describe ACCOUNT_ID
```

### Monitor Real-Time Activity
```bash
# Watch cleanup logs
watch -n 1 'tail -20 logs/cost-management/cleanup-*.log'

# Watch activation logs
watch -n 1 'tail -20 logs/cost-management/activation-*.log'
```

## ⚠️ Important Notes

### Limitations
```
✗ First activation takes 5-10 minutes (cold start)
✗ Cloud SQL tier changes take 2-5 minutes
✗ Cannot have both micro and standard tiers active simultaneously
✗ Redis RDB snapshot takes time on re-enable
```

### Best Practices
```
✓ Commit & push before stopping work (triggers auto-activation for CI)
✓ Use manual activation when resuming after long idle
✓ Monitor logs for cleanup errors
✓ Don't set threshold below 3 minutes (too aggressive)
✓ Always exclude production resources (pattern: *prod*)
```

### Troubleshooting

**Resources not cleaning up?**
```bash
# Check if gcloud auth is valid
gcloud auth list
gcloud auth application-default login

# Check Docker daemon is running
docker ps

# Run cleanup manually with verbose output
bash -x scripts/cost-management/idle-resource-cleanup.sh
```

**Resources not activating?**
```bash
# Check service account permissions
gcloud projects get-iam-policy PROJECT_ID

# Check if services are blocked
gcloud services list --available

# Re-activate manually
bash scripts/cost-management/on-demand-activation.sh --verbose
```

**High costs despite cleanup?**
```bash
# Check for production resources being downgraded
grep "Skipping production" logs/cost-management/cleanup-*.log

# Check for failed cleanups
grep "Failed to" logs/cost-management/cleanup-*.log

# Review billing detail
gcloud billing accounts describe ACCOUNT_ID --format="json"
```

## 🚀 Next Steps

1. **Deploy now**
   ```bash
   chmod +x scripts/cost-management/*.sh
   git add -A
   git commit -m "feat: enable 5-min idle cleanup and on-demand activation"
   git push
   ```

2. **Test cleanup**
   ```bash
   bash scripts/cost-management/idle-resource-cleanup.sh
   ```

3. **Verify activation**
   ```bash
   bash scripts/cost-management/on-demand-activation.sh
   ```

4. **Check savings**
   ```bash
   bash scripts/cost-management/cost-estimation.sh
   ```

---

**Strategy:** Pay only for active development time
**Expected Savings:** 70-80% monthly cost reduction
**Setup Time:** ~5 minutes
**Maintenance:** Zero - fully automated
