# Credential Rotation Checklist

**Date**: March 7, 2026  
**Status**: Post-Security-Remediation Verification  
**Scope**: GitHub, GCP, Vault, Docker Hub, Slack, MinIO

---

## Summary

This checklist verifies that credentials remain valid after security remediation (history purge, secret redaction). The gitleaks findings were **placeholder variables** in documentation (e.g., `GITHUB_TOKEN`, `YOUR_TOKEN` in curl examples), **not actual exposed secrets**.

**No literal secret tokens were found in git history.**

---

## Credential Categories & Verification

### 1. GitHub Credentials ✓ (Check)

**Type**: Personal Access Tokens (PATs), GitHub App Tokens, Deploy Keys  
**Risk**: Medium if exposed in history (now redacted and force-pushed)  
**Action Required**:

- [ ] **PATs**: Verify all GitHub Personal Access Tokens remain active in settings → Developer settings → Personal access tokens
  - Command (for maintainers): `gh auth status` → confirm active token
  - If rotated recently: apply new token to GitHub Secrets & CI/CD environment
  
- [ ] **GitHub Apps**: Verify app private keys remain valid
  - Check: GitHub repo → Settings → GitHub Apps → verify app is authorized
  
- [ ] **Deploy Keys**: Verify SSH deploy keys for CD/CI remain authorized
  - Check: Settings → Deploy keys → confirm SSH keys present
  - If rotated: update in GitHub Secrets + deployment targets

- [ ] **Env Secrets**: Confirm all secrets in GitHub repo → Settings → Secrets & variables remain accessible
  - Key vars to check: `GITHUB_TOKEN`, `GCP_*`, `SLACK_WEBHOOK`, `VAULT_*`, `DOCKER_HUB_*`

---

### 2. GCP Credentials ✓ (Check)

**Type**: Service Account Keys, Workload Identity, OAuth tokens  
**Risk**: Low (not found in history scan; uses OIDC for CI/CD)  
**Action Required**:

- [ ] **Service Account Keys**: Verify GCP service account keys used by CI/CD remain valid
  - Check: GCP Console → Service Accounts → verify active keys
  - Note: Check expiration dates (typically 10 years for JSON keys)
  
- [ ] **Workload Identity**: Verify OIDC federation between GitHub and GCP remains configured
  - Check: GCP → Workload Identity Federation → verify provider + service account binding
  - If changed: update GitHub Secrets: `GCP_WORKLOAD_IDENTITY_PROVIDER`, `GCP_SERVICE_ACCOUNT_EMAIL`

- [ ] **OAuth Tokens (GSM Access)**: Verify access to Google Secret Manager remains authorized
  - Test: Run `gcloud auth list` and confirm service account is active

---

### 3. Vault Credentials ✓ (Check)

**Type**: AppRole credentials, Auth tokens, SSH keys  
**Risk**: Medium if exposed (now redacted)  
**Action Required**:

- [ ] **AppRole Secret ID**: Verify Vault AppRole credentials remain valid (if AppRole auth is used)
  - Command: `vault read auth/approle/role/<ROLE>/secret-id` (maintainer test)
  - If rotated: update GitHub Secrets: `VAULT_ROLE_ID`, `VAULT_SECRET_ID`

- [ ] **SSH Keys stored in Vault**: Verify CI/CD can retrieve SSH keys for signing/auth via Vault
  - Check: SSH key retrieval workflow runs successfully
  
- [ ] **Auth Tokens**: Test Vault login via various auth methods (AppRole, OIDC)
  - Command: `vault login -method=oidc` (test OIDC)

---

### 4. Docker Hub Credentials ✓ (Check)

**Type**: Docker Hub token, registry auth  
**Risk**: Low (not found in history)  
**Action Required**:

- [ ] **Docker Hub Token**: Verify Docker Hub credentials remain valid
  - Command: `docker login` from CI/CD runner (or verify in Secrets)
  - If rotated: update `DOCKER_HUB_USERNAME`, `DOCKER_HUB_TOKEN` in GitHub Secrets

- [ ] **Registry Push Access**: Confirm CI/CD can push to container registry
  - Test: Trigger `docker-build-push` or similar workflow

---

### 5. Slack Credentials ✓ (Check)

**Type**: Slack webhook URL, app tokens, bot tokens  
**Risk**: Medium if exposed (now redacted)  
**Action Required**:

- [ ] **Slack Webhook**: Verify Slack webhook remains valid and active
  - Check: GitHub Secrets → `SLACK_WEBHOOK_URL` exists and is accessible
  - Test: Send test message via workflow or API
  
- [ ] **Slack App Token**: Verify app token for Slack integrations remains valid
  - Check: Slack App → OAuth & Permissions → verify token has required scopes

---

### 6. MinIO Credentials ✓ (Check)

**Type**: MinIO access key, secret key  
**Risk**: Low (not found in history; uses S3 compat auth)  
**Action Required**:

- [ ] **MinIO Access/Secret Keys**: Verify MinIO credentials remain valid
  - Command: `mc ls --profile <minio-alias>` (maintainer test)
  - If rotated: update `MINIO_ACCESS_KEY`, `MINIO_SECRET_KEY` in Vault/GitHub Secrets

---

### 7. SSH Keys ✓ (Check)

**Type**: Deploy SSH keys, CI/CD SSH keys  
**Risk**: High if exposed (now redacted)  
**Action Required**:

- [ ] **Deploy SSH Keys**: Verify SSH keys used for deployment remain authorized
  - Check: Confirm private keys are in GitHub Secrets or Vault
  - Test: SSH to deployment targets (maintainer verification)
  
- [ ] **CI/CD SSH Keys**: Verify SSH keys used by workflows remain valid
  - Command: Run a test SSH workflow (e.g., `ssh -T git@github.com`)

---

### 8. General Security Practices ✓ (Verify)

- [ ] **Secrets Rotation Schedule**: Confirm quarterly or bi-annual credential rotation policy is in place
- [ ] **Audit Logging**: Verify GitHub Actions → audit log shows credential usage patterns (no anomalies)
- [ ] **MFA**: Confirm MFA is enabled for GitHub, GCP, Slack accounts
- [ ] **Pre-commit Secrets Scanner**: Verify `detect-secrets` or similar is running on all commits
- [ ] **No Committed Secrets**: Run final verification: `gitleaks detect --source=local` (should find 0 in working branch)

---

## Rotation Decision Tree

**Q: Do I need to rotate credentials?**

1. **If placeholder variable was redacted from history**: ✅ **No rotation required** (it was a placeholder)
2. **If actual token was exposed**: ⚠️ **Rotate immediately**
   - Delete old credential in source system (GitHub, Vault, etc.)
   - Create new credential with strong random value
   - Update all references in GitHub Secrets, Vault, CI/CD configs
   - Test with new credential before old one expires
3. **If in doubt**: 🔄 **Rotate proactively**
   - Better safe than sorry; rotations are reversible (if new credential doesn't work, revert)
   - Document rotation time/reason in ROTATION_LOG.md

---

## Rotation Log

Track all credential rotations here for audit trail.

| Date | Credential | Type | Reason | Status |
|------|-----------|------|--------|--------|
| 2026-03-07 | - | - | Post-remediation verification | Pending maintainer action |

---

## Next Steps

1. **[ ] Maintainer Review**: Go through each section above and verify credential status
2. **[ ] Rotate if needed**: Use decision tree above to determine if rotation is required
3. **[ ] Document rotations**: Add to rotation log above
4. **[ ] CI/CD Test**: Run a full CI/CD pipeline to confirm all credentials work
5. **[ ] Sign-off**: Once verified, initial and date this checklist

---

## Automation & Monitoring

- **Scheduled Scans**: `gitleaks` runs weekly via `security-audit.yml` workflow
- **Dependabot Monitoring**: GitHub Dependabot alerts for credential leaks (enabled by default)
- **Vault Rotation**: Vault AppRole rotation is automated via `vault-approle-rotation-quarterly.yml` (run quarterly)
- **Slack Rotation**: Slack webhook rotation is automated via `docker-hub-auto-secret-rotation.yml` (run monthly)

---

## References

- Gitleaks Report (pre-remediation): https://gist.github.com/71f8987385b43b0017f7b35cd8fa2f64
- Security Remediation Report: [SECURITY_REMEDIATION_COMPLETE.md](SECURITY_REMEDIATION_COMPLETE.md)
- GitHub Secrets: https://github.com/kushin77/self-hosted-runner/settings/secrets/actions
- GitHub Security Tab: https://github.com/kushin77/self-hosted-runner/security

---

**Checklist Status**: OPEN (awaiting maintainer verification)  
**Last Updated**: March 7, 2026  
**Maintainer Sign-off**: \_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_ (initial + date)
