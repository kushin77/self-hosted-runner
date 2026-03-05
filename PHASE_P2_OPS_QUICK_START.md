# Phase P2: Complete Ops Execution Guide

**Status**: ✅ Engineering 100% Complete → Ready for Ops Deployment  
**Date**: March 5, 2026  
**Next Steps**: Issue #153 → #147 → #154  

---

## TL;DR for Ops

All Phase P2 engineering is **finished and merged to main**. You have:

1. ✅ **Fully automated deployment script** (`./scripts/automation/pmo/deploy-p2-production.sh`)
2. ✅ **Complete documentation** (1,000+ lines)
3. ✅ **Infrastructure prerequisites checklist** (Issue #153)
4. ✅ **10-stage validation checklist** (Issue #154)
5. ✅ **Zero production blockers**

**Execution path**: Infrastructure (2-4 hrs) → Deploy (2-3 hrs) → Validate (1 hr) = 5-8 hours total

---

## Services Ready to Deploy

### provisioner-worker
Terraform provisioning engine. Polls Redis queue, executes terraform apply, persists results.

### managed-auth  
OAuth token management with Vault AppRole integration.

### vault-shim
Secret management abstraction layer (memory/file/Vault backends).

---

## Quick Start

### 1. Gather Infrastructure (Issue #153)
```bash
# Setup deployment host
ssh user@prod-host
sudo apt-get install nodejs npm docker.io

# Export app vaultAppRole credentials
export VAULT_ROLE_ID="<from-vault>"
export VAULT_SECRET_ID="<from-vault>"
export VAULT_ADDR="https://vault.example.com"
export PROVISIONER_REDIS_URL="redis://redis-host:6379"
```

### 2. Deploy (Issue #147)
```bash
cd /home/akushnir/runnercloud
./scripts/automation/pmo/deploy-p2-production.sh all
```

### 3. Validate (Issue #154)
```bash
# Follow 10-stage checklist
docs/PHASE_P2_DEPLOYMENT_VALIDATION_CHECKLIST.md

# Spot check: service should be running
docker ps | grep provisioner
# or
systemctl status provisioner-worker
```

---

## Full Docs

- **Deployment**: [docs/PROVISIONER_WORKER_PROD_ROLLOUT.md](docs/PROVISIONER_WORKER_PROD_ROLLOUT.md)
- **Validation**: [docs/PHASE_P2_DEPLOYMENT_VALIDATION_CHECKLIST.md](docs/PHASE_P2_DEPLOYMENT_VALIDATION_CHECKLIST.md)
- **Architecture**: [docs/PHASE_P2_DELIVERY_SUMMARY.md](docs/PHASE_P2_DELIVERY_SUMMARY.md)
- **Vault Setup**: [docs/VAULT_PROD_SETUP.md](docs/VAULT_PROD_SETUP.md)

---

## GitHub Issues (Sequential)

1. **[#153](https://github.com/kushin77/self-hosted-runner/issues/153)** - Infrastructure Prerequisites
2. **[#147](https://github.com/kushin77/self-hosted-runner/issues/147)** - Deployment Execution
3. **[#154](https://github.com/kushin77/self-hosted-runner/issues/154)** - Validation & Sign-Off
4. **[#146](https://github.com/kushin77/self-hosted-runner/issues/146)** - Phase P3 (post-deployment)

---

## Key Features

- ✅ **idempotency**: Plan-hash prevents duplicate provisioning
- ✅ **Persistence**: Redis queue with job state tracking
- ✅ **Vault Integration**: AppRole-based authentication
- ✅ **Feature Flags**: `USE_TERRAFORM_CLI=0` for stub mode
- ✅ **Automation**: 5-stage orchestrated deployment
- ✅ **Validation**: 10-stage comprehensive checklist

---

## Risk Level: LOW

- Comprehensive validation checklists
- Clear rollback procedure (disable CLI runner)
- Automated deployment reduces manual errors
- Zero technical blockers identified

---

## Success Criteria

- ✅ Services start cleanly
- ✅ 1+ provisioning job succeeds end-to-end
- ✅ jobStore persists results
- ✅ Plan-hash deduplication works
- ✅ Logs clean (no unexpected errors)
- ✅ 1+ hour stable operation

---

## Timeline

Total: **5-8 hours**
- Infrastructure gathering: 2-4 hours
- Deployment execution: 2-3 hours  
- Validation & sign-off: 1+ hour

---

**Status**: ✅ **READY TO DEPLOY**

Start with [Issue #153](https://github.com/kushin77/self-hosted-runner/issues/153) for infrastructure prerequisites.
