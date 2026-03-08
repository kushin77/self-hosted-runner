# 🚀 Operator Quick Start — Secrets Orchestration Setup

**Date:** 2026-03-08  
**Status:** All automation ready; awaiting operator execution  
**Owner:** ops@example.com

---

## ⚡ Do This Now (Choose One Path)

### **Path A: If your environment has working GitHub Actions API + gh CLI**

```bash
# 1. In an environment with AWS/GCP/Vault CLIs configured:
cd infra
chmod +x setup-secrets-orchestration.sh
./setup-secrets-orchestration.sh

# The script will:
# - Apply Terraform templates (GCP WIF, AWS OIDC/KMS, Vault role)
# - Extract outputs and set GitHub repository secrets
# - Display next steps
```

**Next:** See issue #1597 for confirmation steps.

### **Path B: If Actions API is blocked in your environment**

```bash
# 1. Run locally in a secure operator environment:
cd infra
chmod +x local_secrets_health_check.sh
./local_secrets_health_check.sh

# Output: /tmp/local_secrets_health_report.json

# 2. Then manually:
# - Provision GCP WIF, AWS OIDC/KMS, Vault using the .tf templates
# - Set repository secrets: GCP_PROJECT_ID, GCP_WORKLOAD_IDENTITY_PROVIDER, VAULT_ADDR, AWS_KMS_KEY_ID
# - Trigger workflow: gh workflow run 'secrets-health-multi-layer.yml' --ref main
```

**Next:** Share results in issue #1666 (post-validation).

---

## 📋 Verification Checklist

- [ ] Bootstrap script completed (or manual provisioning done)
- [ ] Repository secrets set (check Settings → Secrets)
  - [ ] GCP_PROJECT_ID
  - [ ] GCP_WORKLOAD_IDENTITY_PROVIDER
  - [ ] VAULT_ADDR
  - [ ] AWS_KMS_KEY_ID
- [ ] Health workflow triggered: `gh workflow run 'secrets-health-multi-layer.yml' --ref main`
- [ ] Workflow logs show: Layer 1 ✅ Layer 2 ✅ Layer 3 ✅
- [ ] Artifacts downloaded and reviewed
- [ ] Results attached to issue #1666

---

## 🔗 Related Resources

- **Full Guide:** [OPERATOR_DEPLOYMENT_GUIDE.md](../OPERATOR_DEPLOYMENT_GUIDE.md)
- **Status:** [SECRETS_REMEDIATION_STATUS_MAR8_2026.md](../SECRETS_REMEDIATION_STATUS_MAR8_2026.md)
- **Bootstrap Issue:** [#1597](https://github.com/kushin77/self-hosted-runner/issues/1597)
- **API Block Issue:** [#1598](https://github.com/kushin77/self-hosted-runner/issues/1598)
- **Post-Validation:** [#1666](https://github.com/kushin77/self-hosted-runner/issues/1666)
- **PR:** [#1665](https://github.com/kushin77/self-hosted-runner/pull/1665)

---

## ❓ Troubleshooting

**Q: I got "No OIDC token" error**  
A: This means the runner environment doesn't issue ephemeral OIDC tokens. Use Path B (local check) instead.

**Q: Vault connection failed**  
A: Ensure Vault is deployed and unsealed, and VAULT_ADDR is set correctly in repo secrets.

**Q: KMS describe-key failed**  
A: Ensure AWS credentials are available and AWS_KMS_KEY_ID is set to a valid key in your account.

**Q: All checks pass locally but workflow fails**  
A: Runner environment may have different cloud credentials than operator environment. Check runner IAM role / service account bindings.

---

**Once all green → automation will merge PR #1665 and close incidents automatically.**
