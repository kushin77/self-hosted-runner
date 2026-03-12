# Governance Model & Compliance Framework
## Milestone 2: Secrets & Credential Management

**Effective Date:** 2026-03-12T17:45:00Z  
**Version:** 1.0  
**Status:** ENFORCED (Blocking)  
**Audience:** Development, Operations, Security  

---

## Executive Summary

All infrastructure, deployments, and credential management must comply with 10 core governance principles. These principles ensure:
- ✅ **Immutability** - No data can be modified after creation
- ✅ **Ephemeral Resources** - Auto-cleanup to prevent sprawl
- ✅ **Idempotency** - Safe to re-run without side effects
- ✅ **No Manual Ops** - Fully automated, hands-off execution
- ✅ **Cryptographic Security** - GSM/Vault/KMS for ALL credentials
- ✅ **Direct Development** - Commits to main trigger deployment
- ✅ **Direct Deployment** - No release workflow or GitHub Actions

Non-compliance **blocks deployments** and triggers **incident response**.

---

## 10 Core Governance Principles

### 1. **IMMUTABLE** - No Modifications After Creation

**Definition:** All data created is append-only and cannot be modified or deleted.

**Requirements:**
- ✅ Audit trail stored in immutable JSONL format
- ✅ S3 Object Lock in WORM (Write-Once-Read-Many) mode
- ✅ 365-day retention minimum
- ✅ Database table uses `APPEND_ONLY` constraint
- ✅ Git history never rewritten (except for exposed keys)

**Enforcement:**
```bash
# S3 verification
aws s3api get-object-lock-configuration --bucket nexusshield-audit-immutable

# Database verification
SELECT table_name FROM information_schema.tables 
WHERE table_schema='audit' AND table_name='events';

# Git verification
git log --oneline | head -5
```

**Violation:** Attempting to modify audit data = **INCIDENT**

---

### 2. **EPHEMERAL** - Auto-Cleanup of Resources

**Definition:** All resources auto-cleanup after use; no persistent state outside audit trail.

**Requirements:**
- ✅ Kubernetes pods use `terminationGracePeriodSeconds`
- ✅ Temporary files deleted on pod termination
- ✅ Cloud Run instances scale to zero when idle
- ✅ No orphaned volumes or snapshots
- ✅ CronJob pods marked for garbage collection

**Enforcement:**
```bash
# Pod lifecycle hook
terminationGracePeriodSeconds: 30
lifecycle:
  preStop:
    exec:
      command: ["/bin/sh", "-c", "rm -f /tmp/* && exit 0"]

# Cloud Run cleanup
gcloud run services update --no-traffic-split
```

**Violation:** Persistent state outside audit trail = **CONFIG ERROR**

---

### 3. **IDEMPOTENT** - Safe to Re-Run Without Side Effects

**Definition:** Every operation produces the same result regardless of execution count.

**Requirements:**
- ✅ Terraform plans show zero drift on re-run
- ✅ Database migrations are reversible or idempotent
- ✅ Helm charts use `--install` strategy
- ✅ No duplicate data created on re-execution
- ✅ Manual retries = identical outcome

**Enforcement:**
```bash
# Terraform idempotency check
terraform plan -out=tfplan
grep -q "No changes" tfplan || exit 1

# Helm idempotency
helm upgrade --install \
  --atomic \
  --timeout 5m \
  my-release my-chart
```

**Violation:** Duplicate data or state drift = **DEPLOYMENT FAILURE**

---

### 4. **NO-OPS** - Fully Automated, Zero Manual Intervention

**Definition:** All operations run automatically; no human execution required.

**Requirements:**
- ✅ Cloud Scheduler runs cron jobs daily
- ✅ CronJob in Kubernetes handles pod-based tasks
- ✅ Cloud Build auto-triggered on commit
- ✅ Deployment automated end-to-end
- ✅ Alerts trigger remediation scripts (not Slack)

**Enforcement:**
```bash
# Cloud Scheduler setup
gcloud scheduler jobs create app-engine daily-backup \
  --schedule="0 2 * * *" \
  --http-method=POST \
  --uri=https://project.cloudfunctions.net/backup

# CronJob in Kubernetes
apiVersion: batch/v1
kind: CronJob
metadata:
  name: audit-export
spec:
  schedule: "0 * * * *"
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: audit-exporter
          containers:
          - name: exporter
            image: gcr.io/project/audit-exporter:latest
            command: ["bash", "-c", "scripts/ops/export-audit.sh"]
```

**Violation:** Manual step required = **PROCESS FAILURE**

---

### 5. **HANDS-OFF** - No Password Rotation, OIDC Auth Only

**Definition:** Credentials are auto-managed; no human rotation required.

**Requirements:**
- ✅ Workload Identity (GCP) for pod auth
- ✅ OIDC token exchange (no passwords)
- ✅ Service account JSON never committed to git
- ✅ Tokens auto-refreshed by libraries
- ✅ No SSH keys or personal credentials

**Enforcement:**
```bash
# Workload Identity binding
gcloud iam service-accounts add-iam-policy-binding \
  cloud-build-sa@project.iam.gserviceaccount.com \
  --role=roles/iam.workloadIdentityUser

# Pod annotation
apiVersion: v1
kind: ServiceAccount
metadata:
  name: audit-exporter
  annotations:
    iam.gke.io/gcp-service-account: audit-exporter@project.iam.gserviceaccount.com

# No password in code!
```

**Violation:** Hardcoded credentials = **SECURITY INCIDENT**

---

### 6. **GSM/VAULT/KMS ONLY** - No Hardcoded Secrets

**Definition:** ALL credentials stored in secret backend; ZERO plaintext in git.

**Requirements:**
- ✅ Google Secret Manager (GCP preferred) OR
- ✅ HashiCorp Vault (on-premises) OR
- ✅ AWS KMS (fallback only)
- ✅ ZERO hardcoded passwords, tokens, keys
- ✅ ZERO git-crypt or encrypted files
- ✅ ZERO environment variables in manifests
- ✅ Secret versioning enabled
- ✅ Audit trail on secret access

**Enforcement - Option A: GSM**
```bash
# Store secret in GSM
echo "db-password-here" | gcloud secrets create db-password \
  --data-file=- \
  --replication-policy="auto"

# Reference in pod via CSI driver
apiVersion: v1
kind: SecretProviderClass
metadata:
  name: db-secrets
spec:
  provider: gcp
  parameters:
    secrets: |-
      - resourceName: "projects/PROJECT_ID/secrets/db-password/versions/latest"
        path: "db-password"
---
apiVersion: v1
kind: Pod
metadata:
  name: app
spec:
  containers:
  - name: app
    volumeMounts:
    - name: secrets-store
      mountPath: "/mnt/secrets"
      readOnly: true
  volumes:
  - name: secrets-store
    csi:
      driver: secrets-store.csi.k8s.io
      readOnly: true
      volumeAttributes:
        secretProviderClass: "db-secrets"
```

**Enforcement - Option B: Vault**
```bash
# Store secret in Vault
vault kv put secret/db password=db-password-here

# Reference in pod via Vault Agent
annotations:
  vault.hashicorp.com/agent-inject: "true"
  vault.hashicorp.com/agent-inject-secret-database: "secret/db"
  vault.hashicorp.com/role: "myapp"
```

**Enforcement - Option C: AWS KMS (Fallback)**
```bash
# Store in KMS (last resort)
aws kms encrypt \
  --key-id arn:aws:kms:region:account:key/id \
  --plaintext "db-password-here"
```

**Violation:** Hardcoded secret found = **AUTOMATIC BLOCK + ROTATION**

---

### 7. **DIRECT DEVELOPMENT** - Commits to Main Trigger Build

**Definition:** Every commit to main automatically triggers the CI/CD pipeline.

**Requirements:**
- ✅ Cloud Build webhook (push → build)
- ✅ No PR approval gates before build
- ✅ Every commit = potential deployment
- ✅ Build pipeline immutable (cloudbuild.yaml in git)
- ✅ Build artifacts tagged with commit SHA

**Enforcement:**
```bash
# Cloud Build webhook configured in GCP Console
# Settings → Triggers → Create new trigger
# Trigger: refs/heads/main
# Build config: cloudbuild.yaml

# Image tagging (immutable)
docker tag myapp gcr.io/project/myapp:${COMMIT_SHA}
docker tag myapp gcr.io/project/myapp:latest
```

**Violation:** PR-based approval gate = **POLICY VIOLATION**

---

### 8. **DIRECT DEPLOYMENT** - Cloud Build → Cloud Run/GKE

**Definition:** Deployment happens directly; no release workflow or manual promotion.

**Requirements:**
- ✅ Build → Artifact Registry (Cloud Build step)
- ✅ Deploy → Cloud Run or GKE (Cloud Build step)
- ✅ NO GitHub Release workflow
- ✅ NO git tag + release notes
- ✅ NO manual promotion gates
- ✅ Every commit = immutable audit record

**Enforcement - cloudbuild.yaml:**
```yaml
steps:
  # Step 1: Build image
  - name: 'gcr.io/cloud-builders/docker'
    args: ['build', '-t', 'gcr.io/$PROJECT_ID/myapp:$COMMIT_SHA', '.']

  # Step 2: Push to Artifact Registry
  - name: 'gcr.io/cloud-builders/docker'
    args: ['push', 'gcr.io/$PROJECT_ID/myapp:$COMMIT_SHA']

  # Step 3: Deploy to Cloud Run
  - name: 'gcr.io/cloud-builders/gke-deploy'
    args: ['run', '--filename=k8s/', '--image=gcr.io/$PROJECT_ID/myapp:$COMMIT_SHA']

  # Step 4: Verify deployment
  - name: 'gcr.io/cloud-builders/kubectl'
    args: ['rollout', 'status', 'deployment/myapp']
    env:
      - 'CLOUDSDK_COMPUTE_ZONE=us-central1-c'
      - 'CLOUDSDK_CONTAINER_CLUSTER=my-cluster'

  # Step 5: Log to immutable audit trail
  - name: 'gcr.io/cloud-builders/gcloud'
    args: ['storage', 'cp', '/workspace/build-log.json', 'gs://nexusshield-audit-immutable/builds/']

substitutions:
  _ENVIRONMENT: 'production'

onFailure:
  - name: 'gcr.io/cloud-builders/gcloud'
    args: ['logging', 'write', 'deployment-failures', 'Build failed: $BUILD_ID']
```

**Violation:** Manual promotion or release workflow = **POLICY VIOLATION**

---

### 9. **NO GITHUB ACTIONS** - Forbidden (Third-Party Risk)

**Definition:** GitHub Actions workflows are explicitly prohibited.

**Requirements:**
- ✅ NO `.github/workflows/*.yml` files
- ✅ NO `uses: actions/*` directives
- ✅ NO workflows triggered on `push:` or `pull_request:`
- ✅ GitHub Actions disabled in repository settings
- ✅ All CI/CD via Cloud Build only

**Why Prohibited:**
- ❌ Third-party infrastructure (not self-hosted)
- ❌ Credentials exposed in workflow context
- ❌ Logs visible to GitHub (not auditable)
- ❌ Impossible to ensure immutability
- ❌ Violates "hands-off, no-ops" requirement

**Enforcement:**
```bash
# Pre-merge gate: BLOCK if workflows exist
if find .github/workflows -type f | grep -q .; then
  echo "ERROR: GitHub Actions workflows found"
  exit 1
fi

# Repository settings (manual)
# Settings → Actions and workflows → Disable
```

**Violation:** GitHub Actions workflow created = **IMMEDIATE REMOVAL + INCIDENT**

---

### 10. **NO GITHUB PULL RELEASES** - Forbidden

**Definition:** GitHub Releases and manual versioning are prohibited.

**Requirements:**
- ✅ NO `gh release create` commands
- ✅ NO git tag + release notes workflow
- ✅ NO semantic versioning in Release API
- ✅ NO Draft Release states
- ✅ Deployment = direct commit + audit entry

**Why Prohibited:**
- ❌ Manual workflow violates "no-ops"
- ❌ Breaks "direct deployment" model
- ❌ Creates decision point (human intervention)
- ❌ No immutable record per deployment

**Enforcement:**
```bash
# Pre-merge gate: BLOCK if release commands found
if grep -r 'gh release create' . && ! grep -q 'docs'; then
  echo "ERROR: GitHub release automation found"
  exit 1
fi
```

**Violation:** Release automation detected = **AUTOMATIC REMOVAL**

---

## Compliance Verification

### Pre-Merge Gates (Required Before Every Merge)

```bash
./scripts/governance/pre-merge-gates.sh
```

**Gates:**
1. ✅ No hardcoded secrets (gitleaks)
2. ✅ No GitHub Actions workflows
3. ✅ Credentials → GSM/Vault/KMS
4. ✅ No GitHub Release automation
5. ✅ Cloud Build configured
6. ✅ Immutable audit trail
7. ✅ No AWS Secrets Manager
8. ✅ No secrets in env vars
9. ✅ Terraform valid
10. ✅ OIDC auth configured

**Exit Code:**
- `0` = PASS (safe to merge)
- `1` = FAIL (block merge)

### Audit Trail Format

All compliance records logged to immutable JSONL:

```json
{
  "timestamp": "2026-03-12T17:45:00Z",
  "action": "pre-merge-gates-passed",
  "commit": "a1b2c3d",
  "branch": "main",
  "gates_passed": 10,
  "gates_failed": 0,
  "actor": "cloud-build-sa@project.iam.gserviceaccount.com"
}
```

---

## Non-Compliance Consequences

| Violation | Immediate Action | Timeline |
|-----------|------------------|----------|
| Hardcoded secret | Merge blocked | N/A |
| GitHub Actions | Workflow deleted | Immediate |
| Hardcoded credentials | Secret rotated | 1 hour |
| Manual release | Release deleted | Immediate |
| No audit trail | Deployment failed | N/A |
| Key exposure | History rewritten | 4 hours |

---

## Implementation Checklist

- [x] Pre-merge gates script created
- [x] Governance policy documented
- [x] 10 principles defined
- [x] Audit trail immutable
- [x] Cloud Build configured
- [x] Secret backend (GSM) set up
- [x] OIDC auth enabled
- [x] GitHub Actions disabled
- [x] Release automation removed
- [x] All issues annotated with governance requirements

---

## Contact

**Questions?** Refer to [GOVERNANCE_COMPLIANCE_TRACKER.md](./GOVERNANCE_COMPLIANCE_TRACKER.md)

**Issues?** Create a new GitHub issue with label `governance-violation`

---

**Last Updated:** 2026-03-12T17:45:00Z  
**Version:** 1.0  
**Status:** ENFORCED (Blocking deployments)
