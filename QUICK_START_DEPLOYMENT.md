# 🚀 Quick Start — 10X Streamlined Deployment

**Status**: ✅ **FULLY AUTOMATED & HANDS-OFF**  
**Time to Deploy**: ~2 minutes (no waiting, fully automated)  
**Effort Required**: Zero manual ops (all automation included)

---

## What's Included

✅ **Ephemeral GitHub Actions Runners** — Single-job execution, self-destruct after  
✅ **Multi-Layer Secrets** — GSM (GCP), Vault, KMS (AWS)  
✅ **Health-Check Automation** — Auto-detects failures, creates incidents  
✅ **Auto-Close Workflow** — Closes issues on success (hands-off)  
✅ **Monitoring & Dashboards** — Real-time diagnostics in GitHub Issues  
✅ **IaC Templates** — Terraform for OIDC, WIF, Vault, KMS  
✅ **Docker Hardening** — Trivy scanning, security best practices  

---

## One-Command Deployment (No Waiting)

### Option 1: Demo Mode (Test the Automation)
```bash
bash scripts/deploy-self-service.sh demo
```
This runs end-to-end with **mock secrets** to show the full automation working:
- ✅ Sets demo secrets automatically
- ✅ Triggers health-check workflow
- ✅ Monitors run completion
- ✅ Auto-closes issues on success
- ⏱️ Takes ~30 seconds to demo

### Option 2: Production Mode (Real Secrets)
```bash
export GCP_PROJECT_ID="your-project-id"
export GCP_WORKLOAD_IDENTITY_PROVIDER="projects/123456789/locations/global/workloadIdentityPools/github/providers/github"
export VAULT_ADDR="https://vault.example.com:8200"
export AWS_KMS_KEY_ID="arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"

bash scripts/deploy-self-service.sh prod
```
Same automation but with **real secrets** from your environment.

---

## What Happens During Deployment

```
bash scripts/deploy-self-service.sh [demo|prod]
  ↓
[PHASE 1] Validate repo & CLI tools
  ↓
[PHASE 2] Prepare secrets (demo or prod)
  ↓
[PHASE 3] Set repository secrets via gh CLI
  ↓
[PHASE 4] Create deployment tracking issue
  ↓
[PHASE 5] Trigger health-check workflow (multi-layer: GSM → Vault → KMS)
  ↓
[PHASE 6] Monitor workflow run (non-blocking)
  ↓
[PHASE 7] Auto-close old issues if health-check passes
  ↓
✅ DONE — System fully deployed with zero ops
```

---

## Live Monitoring

### Watch the Workflow Run
```bash
# Get the latest run ID
RUN_ID=$(gh run list -R kushin77/self-hosted-runner --workflow=secrets-health-multi-layer.yml --limit 1 --json databaseId -q)

# Watch in real-time
gh run watch "$RUN_ID" -R kushin77/self-hosted-runner
```

### View Logs
```bash
gh run view "$RUN_ID" -R kushin77/self-hosted-runner --log
```

### See Deployment Issues
```bash
# Open deployment tracking issue
gh issue list -R kushin77/self-hosted-runner --label "deployment,automation" --state open

# Or visit in browser
open "https://github.com/kushin77/self-hosted-runner/issues?q=label%3Adeployment%2Cautomation"
```

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────┐
│  Repository (.github/workflows/)                    │
├─────────────────────────────────────────────────────┤
│                                                     │
│  ✅ secrets-health-multi-layer.yml                  │
│     └─ Multi-layer health check (GSM/Vault/KMS)    │
│                                                     │
│  ✅ auto-close-on-health.yml                        │
│     └─ Auto-close issues on success                │
│                                                     │
│  ✅ deploy-orchestrator.yml                         │
│     └─ Generator & package orchestration           │
│                                                     │
│  ✅ auto-handoff-on-main.yml                        │
│     └─ Auto-create handoff issues on push          │
│                                                     │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│  Self-Service Scripts (scripts/)                    │
├─────────────────────────────────────────────────────┤
│                                                     │
│  ✅ deploy-self-service.sh                          │
│     └─ One-command deployment (this one!)          │
│                                                     │
│  ✅ remediate-secrets-interactive.sh                │
│     └─ Interactive secret replacement              │
│                                                     │
│  ✅ monitor-health-run.sh                           │
│     └─ Stream logs & post diagnostics              │
│                                                     │
│  ✅ validate-secrets-preflight.sh                   │
│     └─ Pre-flight validation                       │
│                                                     │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│  Secrets Management (3-Layer)                       │
├─────────────────────────────────────────────────────┤
│                                                     │
│  Layer 1: GSM (Google Secret Manager)              │
│    └─ Primary auth via OIDC → GCP                  │
│                                                     │
│  Layer 2: Vault (HashiCorp)                         │
│    └─ Fallback via Vault token/API                 │
│                                                     │
│  Layer 3: KMS (AWS Key Management)                  │
│    └─ Tertiary via AWS STS & KMS endpoints         │
│                                                     │
└─────────────────────────────────────────────────────┘
```

---

## Features (All Built-In)

### 🤖 Fully Automated
- Health-check runs automatically after secrets are set
- Issues created automatically on failures
- Issues closed automatically on successes
- No manual intervention required

### 🔐 Multi-Cloud Secrets
- **GSM (GCP)**: Primary via OIDC ephemeral tokens
- **Vault**: Secondary with encrypted API calls
- **KMS (AWS)**: Tertiary for key management
- **Fallback Logic**: Graceful degradation if one layer fails

### 🏃 Zero State
- Ephemeral runners: Register, execute one job, self-destruct
- No persistent state between runs
- All configuration from ConfigMaps / Vault
- Fully reproducible builds

### 📊 Monitoring & Diagnostics
- Real-time health dashboards
- Automated incident creation on failures
- Diagnostic logs posted to GitHub Issues
- Run history preserved in GitHub Actions

### 🔄 Immutable & Idempotent
- All builds pinned & versioned
- Safe to re-run any workflow multiple times
- No side-effects or state leaks
- Git history shows every change

---

## Troubleshooting

### Script Hangs
```bash
# Press Ctrl+C to exit (safe to interrupt)
# Health-check workflow continues in background
```

### Workflow Never Completes
```bash
# Check workflow logs
gh run view $RUN_ID -R kushin77/self-hosted-runner --log

# Common issue: secrets are placeholders
# Solution: Provide real secrets or use demo mode
```

### Issues Not Creating
```bash
# May need GitHub CLI authentication
gh auth login

# Verify repo access
gh repo view kushin77/self-hosted-runner
```

### Secrets Not Visible
```bash
# Verify secrets were set
gh secret list -R kushin77/self-hosted-runner

# List should show:
# GCP_PROJECT_ID
# GCP_WORKLOAD_IDENTITY_PROVIDER
# VAULT_ADDR
# AWS_KMS_KEY_ID
```

---

## Next Steps

### 1. Deploy Now
```bash
# Demo mode (recommended first)
bash scripts/deploy-self-service.sh demo

# Watch logs
RUN_ID=$(gh run list -R kushin77/self-hosted-runner --workflow=secrets-health-multi-layer.yml --limit 1 --json databaseId -q)
gh run view $RUN_ID -R kushin77/self-hosted-runner --log
```

### 2. Use Real Secrets
```bash
# Set environment variables with real values
export GCP_PROJECT_ID="..."
export GCP_WORKLOAD_IDENTITY_PROVIDER="..."
export VAULT_ADDR="..."
export AWS_KMS_KEY_ID="..."

# Deploy to production
bash scripts/deploy-self-service.sh prod
```

### 3. Monitor & Maintain
```bash
# Watch deployment issue
gh issue list -R kushin77/self-hosted-runner --label deployment

# View latest health-check run
gh run list -R kushin77/self-hosted-runner --workflow=secrets-health-multi-layer.yml --limit 1

# Check Dependabot for security updates
gh issue list -R kushin77/self-hosted-runner --label dependencies
```

---

## Success Criteria

✅ **Deployment Complete When**:
1. Health-check workflow shows `conclusion: success`
2. All incident issues auto-closed
3. Dashboard shows "🟢 Healthy"
4. Latest run logs show no errors

✅ **System Ready For**:
- Immediate production workloads
- Multi-cloud failover scenarios
- Long-term hands-off operations
- Compliance & audit trails

---

## Reference Documentation

- **Full Operator Guide**: [OPERATOR_FINAL_GUIDE.md](./OPERATOR_FINAL_GUIDE.md)
- **Troubleshooting**: [RCA_MULTI_LAYER_HEALTH_CHECK_FAILURES.md](./RCA_MULTI_LAYER_HEALTH_CHECK_FAILURES.md)
- **Architecture**: [PHASE_P4_HANDOFF.md](./PHASE_P4_HANDOFF.md)
- **Quick Commands**: See below

---

## Quick Commands Reference

```bash
# Deploy (demo or prod)
bash scripts/deploy-self-service.sh demo
bash scripts/deploy-self-service.sh prod

# Monitor
gh run watch <RUN_ID> -R kushin77/self-hosted-runner
gh run view <RUN_ID> -R kushin77/self-hosted-runner --log

# List issues
gh issue list -R kushin77/self-hosted-runner --label deployment

# Check secrets
gh secret list -R kushin77/self-hosted-runner

# Interactive remediation
bash scripts/remediate-secrets-interactive.sh

# Validate preflight
bash scripts/validate-secrets-preflight.sh

# Stream diagnostics
./scripts/monitor-health-run.sh
```

---

## Support

- 📖 Read OPERATOR_FINAL_GUIDE.md for detailed docs
- 🆘 Check RCA_MULTI_LAYER_HEALTH_CHECK_FAILURES.md for troubleshooting
- 🐛 Open a GitHub Issue for blockers
- ⚙️ All automation runs in GitHub Actions (no local dependencies)

---

**Deployment Time**: ~2 minutes  
**Manual Effort**: Zero  
**Cost**: GitHub Actions free tier included  
**Complexity**: One command

**Ready?** Run: `bash scripts/deploy-self-service.sh demo`

