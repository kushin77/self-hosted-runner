# Hands-Off GitLab Runner Deployment — Complete Guide

**Status**: Ready for Immediate Execution (March 6, 2026)  
**Owner**: Platform/CI Operator  
**Goal**: Deploy a fully automated, immutable, sovereign, ephemeral Kubernetes-based GitLab Runner using hands-off CI and GCP Secret Manager

---

## Executive Summary

This repository now contains a complete, production-ready implementation for deploying GitLab Runner on Kubernetes with zero manual intervention during deployment. The deployment uses:

- **GCP Secret Manager** for secure secret storage (kubeconfig, registration token)
- **Protected GitLab CI jobs** to maintain secrets outside the repository
- **Helm** for idempotent Kubernetes installation
- **SealedSecrets** (optional) for additional secrets encryption
- **Ephemeral pods** for each job (no persistent container state)
- **Fully automated validation** with pre-flight and post-deploy checks

---

## Quick Start (5 steps)

If you have GCP and GitLab access, deploy in minutes:

### Step 1: Create GCP Secrets
```bash
# In GCP console or via gcloud, create three secrets in Secret Manager (project: gcp-eiq):

# 1. Kubeconfig
base64 -w0 ~/.kube/config | gcloud secrets versions add kubeconfig-secret --data-file=- --project=gcp-eiq

# 2. Registration Token (get from GitLab > Admin > Runners > New Group Runner)
echo -n "glrt-<token>" | gcloud secrets versions add gitlab-runner-regtoken --data-file=- --project=gcp-eiq

# 3. Service Account Key (create SA with secretmanager.secretAccessor role)
base64 -w0 ~/.config/gcp/sa-key.json | gcloud secrets versions add gcp-sa-key --data-file=- --project=gcp-eiq
```

### Step 2: Set GitLab CI Protected Variables
In GitLab (Group or Project > Settings > CI/CD > Variables), add these **protected, masked** variables:
- `GCP_PROJECT` = `gcp-eiq`
- `GCP_SA_KEY` = base64-encoded service account JSON key
- `KUBECONFIG_SECRET_NAME` = `kubeconfig-secret`
- `REGTOKEN_SECRET_NAME` = `gitlab-runner-regtoken`

### Step 3: Trigger Pipeline
In GitLab UI: **Pipelines** → **Run pipeline** → select `main` → **Create pipeline**

### Step 4: Start Manual Job
In the created pipeline, locate and click **▶ deploy:sovereign-runner-gsm** (manual job)

### Step 5: Validate
Monitor job logs. Once complete (status: Passed):
```bash
# From a terminal with kubectl access:
kubectl -n gitlab-runner get pods
kubectl -n gitlab-runner logs -l app=gitlab-runner --tail=50
```

---

## Detailed Phases

### Phase 1: Prerequisites & GCP Setup (Issue #102)
**Time**: 15 minutes  
**Who**: Platform operator with GCP access

- [ ] Enable GCP Secret Manager API on project `gcp-eiq`
- [ ] Create service account with `secretmanager.secretAccessor` role
- [ ] Create three secrets in Secret Manager (kubeconfig, regtoken, SA key)
- [ ] Verify with `gcloud secrets versions access latest --secret=<name> --project=gcp-eiq`

**Artifacts**: Three secrets in GCP Secret Manager  
**See**: [issues/102-gsm-secrets-setup.md](issues/102-gsm-secrets-setup.md)

---

### Phase 2: Configure GitLab CI Variables (Issue #101 variant)
**Time**: 5 minutes  
**Who**: Platform operator with GitLab Maintainer/Owner access

- [ ] In GitLab UI, navigate to Group/Project Settings > CI/CD > Variables
- [ ] Add four protected, masked variables:
  - `GCP_PROJECT`
  - `GCP_SA_KEY`
  - `KUBECONFIG_SECRET_NAME`
  - `REGTOKEN_SECRET_NAME`
- [ ] Save variables

**Artifacts**: Protected CI variables configured  
**See**: [issues/101-deploy-via-ci.md](issues/101-deploy-via-ci.md)

---

### Phase 3: Trigger & Monitor Deploy (Issue #103)
**Time**: 5-10 minutes (automated job runs ~2-5 min)  
**Who**: GitLab pipeline executor (usually CI/CD agent or operator)

- [ ] In GitLab, run pipeline on `main` branch
- [ ] Click the ▶️ play icon next to `deploy:sovereign-runner-gsm` job
- [ ] Monitor logs in real-time:
  - GCP authentication
  - Secret fetch from GSM
  - SealedSecret/Secret creation
  - Helm install/upgrade
  - Pod readiness checks

**Expected Logs**:
```
Activating service account...
Fetching kubeconfig secret: kubeconfig-secret
Fetching registration token secret: gitlab-runner-regtoken
SealedSecret generated: infra/gitlab-runner/sealedsecret.generated.yaml
Helm install/upgrade gitlab-runner ...
Waiting for pods to be ready...
✓ All pods are ready
```

**Status**: Passed (green) = success, Failed (red) = check logs for errors

**Artifacts**: `/etc/gitlab-runner/config.toml` and Helm release on Kubernetes  
**See**: [issues/103-trigger-ci-deploy.md](issues/103-trigger-ci-deploy.md)

---

### Phase 4: Post-Deploy Validation (Issue #104)
**Time**: 5-15 minutes  
**Who**: Platform operator with Kubernetes access

#### 4a: Verify Runner Pods
```bash
kubectl -n gitlab-runner get pods -o wide
# Expected: gitlab-runner-0 (or similar) in Running state
```

#### 4b: Check Logs
```bash
kubectl -n gitlab-runner logs -l app=gitlab-runner --tail=100
# Expected: successful registration, ready to accept jobs
```

#### 4c: Verify Registration in GitLab
In GitLab Admin > Runners, confirm:
- Runner name shows as "kubernetes" or "gitlab-runner"
- Status: `Online` (green)
- Tags: `k8s-runner, sovereign, ephemeral, immutable`

#### 4d: Run Validation Pipeline (YAMLtest-sovereign-runner)
```bash
# Trigger via UI: Pipelines > Run pipeline > main
# -or- via CLI:
GITLAB_API_TOKEN=<token> PROJECT_ID=<id> ./scripts/ci/trigger_yamltest_pipeline.sh main
```

Expected behavior:
- `.pre` stage runs `YAMLtest-sovereign-runner`
- Job pulls alpine image
- Runs cluster checks (kubectl commands)
- Status: Passed

**Artifacts**: Passing pipeline with runner validation  
**See**: [issues/104-post-deploy-validation.md](issues/104-post-deploy-validation.md)

---

### Phase 5: Migration & Legacy Runner Decommission (Issue #105)
**Time**: 2-10 days (24-48h validation + 7-day rollback window)  
**Who**: Platform operator with GitLab admin access

#### Timeline:
- **Day 1-2**: Dual-runner period (both old and new online)
  - Run 3+ test pipelines
  - Monitor logs and timings
  - No regressions observed
  
- **Day 3**: Disable legacy runner(s) in GitLab
  - In Admin > Runners, toggle legacy runner(s) offline
  - In-flight jobs complete on legacy runner
  - New jobs go to k8s-runner
  
- **Day 3-10**: Rollback window
  - Keep disabled legacy runner available
  - If critical issue: re-enable legacy, disable new, investigate
  
- **Day 10+**: Cleanup
  - Delete legacy runner registration (remove from GitLab)
  - Archive old logs/metrics
  - Document lessons learned

**Success Criteria**:
- Job success rate > 99%
- Job duration variance < ±10% from baseline
- No stuck jobs or queue backlog
- Pods create/destroy cleanly

**Artifacts**: No legacy runners in GitLab; all jobs on k8s-runner  
**See**: [issues/105-runner-migration-decommission.md](issues/105-runner-migration-decommission.md)

---

## Advanced: Local Testing (if CI path not available)

If you prefer to test locally before committing to CI, or your environment has limited CI capability:

### Provision Local KinD Cluster
```bash
./scripts/ci/provision_kind_cluster.sh gitlab-runner-test
```

### Install kubeseal (for SealedSecrets)
```bash
./scripts/ci/install_kubeseal_helper.sh 0.20.0
export PATH="$PWD/infra/tools:$PATH"
```

### Generate & Apply Secret
```bash
export REG_TOKEN="glrt-<token>"
./scripts/ci/create_sealedsecret_from_token.sh "$REG_TOKEN" gitlab-runner
kubectl apply -f infra/gitlab-runner/sealedsecret.generated.yaml
```

### Deploy Locally
```bash
export KUBECONFIG=$HOME/.kube/config
./scripts/ci/hands_off_runner_deploy.sh
```

### Validate Locally
```bash
kubectl -n gitlab-runner get pods
./scripts/ci/validate_runner_readiness.sh
```

---

## Troubleshooting

### Deploy Job Fails: "GCP authentication failed"
- Verify `GCP_SA_KEY` is valid base64-encoded JSON
- Check service account has `secretmanager.secretAccessor` role
- Verify `GCP_PROJECT` is correct

### Deploy Job Fails: "Secret not found"
- Verify `KUBECONFIG_SECRET_NAME` and `REGTOKEN_SECRET_NAME` match actual GCP secrets
- List secrets: `gcloud secrets list --project=gcp-eiq`

### Pods Stuck in Pending
- Check events: `kubectl -n gitlab-runner describe pod <pod-name>`
- Common causes: image pull errors, resource limits, node selectors
- Check image availability: `kubectl get nodes && docker images | grep gitlab`

### Runner Not Appearing in GitLab UI
- Check logs for registration errors: `kubectl -n gitlab-runner logs -f`
- Verify registration token is valid and not expired
- Check that the correct Helm values were used (including runner tags)

### YAMLtest-sovereign-runner Job Pending
- Runner may not be ready yet; wait 30-60 seconds
- Verify runner pod is in Running state
- Check if runner is picking up jobs: `kubectl -n gitlab-runner logs -l app=gitlab-runner | grep job`

---

## Automation Scripts

This repository includes several helper scripts for fully automated operations:

### `scripts/ci/hands_off_orchestrate.sh`
Master orchestration script that coordinates all phases:
```bash
# Check prerequisites only
./scripts/ci/hands_off_orchestrate.sh check

# Deploy (requires REG_TOKEN, assumes phase_check passed)
REG_TOKEN=glrt-... ./scripts/ci/hands_off_orchestrate.sh deploy

# Validate deployment
./scripts/ci/hands_off_orchestrate.sh validate

# Show migration checklist
./scripts/ci/hands_off_orchestrate.sh migrate

# Cleanup (destructive; asks for confirmation)
./scripts/ci/hands_off_orchestrate.sh cleanup
```

### `scripts/ci/gcp_fetch_secrets.sh`
Fetch kubeconfig and regtoken from GCP Secret Manager (used by CI job):
```bash
./scripts/ci/gcp_fetch_secrets.sh <GCP_PROJECT> <KUBECONFIG_SECRET> <REGTOKEN_SECRET>
```

### `scripts/ci/create_sealedsecret_from_token.sh`
Generate SealedSecret or plain Secret from registration token:
```bash
export REG_TOKEN=glrt-...
./scripts/ci/create_sealedsecret_from_token.sh "$REG_TOKEN" gitlab-runner
```

### `scripts/ci/hands_off_runner_deploy.sh`
Perform idempotent Helm install/upgrade:
```bash
export KUBECONFIG=~/.kube/config
./scripts/ci/hands_off_runner_deploy.sh
```

### `scripts/ci/validate_runner_readiness.sh`
Verify pod readiness and cluster connectivity:
```bash
./scripts/ci/validate_runner_readiness.sh
```

### `scripts/ci/trigger_yamltest_pipeline.sh`
Trigger the pre-flight validation pipeline via GitLab API:
```bash
GITLAB_API_TOKEN=glpat-... PROJECT_ID=12345 ./scripts/ci/trigger_yamltest_pipeline.sh main
```

---

## Key Design Principles

✅ **Immutable**: Each pod is ephemeral; no persistent state on runners  
✅ **Sovereign**: No external dependencies; uses standard Kubernetes and Helm  
✅ **Ephemeral**: Pods are created per job, destroyed after job completes  
✅ **Independent**: Hands-off CI does not require local workstation access  
✅ **Fully Automated**: All deployment steps in CI; no manual kubectl executions needed  
✅ **Secrets-Safe**: Kubeconfig and token fetched from GCP at runtime; never stored in Git  

---

## Repository Artifacts

- `.gitlab-ci.yml` — Main CI config with pre-flight job and runner deploy include
- `.gitlab/ci-includes/runner-deploy.gitlab-ci.yml` — Protected/manual deploy jobs (standard + GSM variant)
- `infra/gitlab-runner/` — Helm values templates, example SealedSecret, README, runbook
- `scripts/ci/` — All helper and deployment automation scripts
- `issues/` — Numbered checklists for each deployment phase (#100-#105)

---

## Support & Questions

If you encounter issues:
1. Check the relevant issue (#102-#105) for your phase
2. Review troubleshooting section above
3. Check runner logs: `kubectl -n gitlab-runner logs -l app=gitlab-runner`
4. Check pod events: `kubectl -n gitlab-runner describe pods`

---

## Timeline & Next Steps

**Immediate (Today)**:
- [ ] Set up GCP secrets (#102)
- [ ] Configure GitLab CI variables (#101)
- [ ] Trigger deploy job (#103)

**Short-term (24-48h)**:
- [ ] Validate runner (#104)
- [ ] Run test pipelines
- [ ] Confirm no regressions

**Medium-term (3-10 days)**:
- [ ] Disable legacy runners (#105)
- [ ] Monitor for issues
- [ ] Perform cleanup

---

**Last Updated**: 2026-03-06  
**Status**: Ready for Execution  
**Approval**: User approved "all the above" — proceed with full hands-off deployment
