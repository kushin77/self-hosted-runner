# 🎯 ADMIN ACTIVATION COMMAND: PHASE 3B CREDENTIAL INJECTION
**Status:** Ready for execution  
**Authority:** User-approved  
**Timeline:** ~15 minutes to production-ready

---

## ONE-LINER ACTIVATION COMMANDS

### Recommended: CLI Method (Safest)
```bash
# STEP 1: Set AWS credentials
./scripts/phase3b-credential-manager.sh set-aws \
  --key REDACTED_AWS_ACCESS_KEY_ID \
  --secret REDACTED_REDACTED_AWS_SECRET_ACCESS_KEY

# STEP 2: Verify (optional, recommended)
./scripts/phase3b-credential-manager.sh verify

# STEP 3: Activate
./scripts/phase3b-credential-manager.sh activate
```

---

### Alternative 1: Environment Variables
```bash
# Set credentials in environment
export AWS_ACCESS_KEY_ID=REDACTED_AWS_ACCESS_KEY_ID
export REDACTED_AWS_SECRET_ACCESS_KEY=REDACTED_REDACTED_AWS_SECRET_ACCESS_KEY

# Optional: Vault
export VAULT_ADDR=https://vault.example.com:8200
export VAULT_NAMESPACE=admin

# Run activation
bash scripts/phase3b-credentials-inject-activate.sh
```

---

### Alternative 2: GitHub Actions (Web UI)
```
1. Open: https://github.com/kushin77/self-hosted-runner/actions
2. Select: "Phase 3B Credential Injection"
3. Click: "Run workflow" (dropdown button)
4. enter credentials:
   - AWS_ACCESS_KEY_ID: REDACTED_AWS_ACCESS_KEY_ID
   - REDACTED_AWS_SECRET_ACCESS_KEY: REDACTED_REDACTED_AWS_SECRET_ACCESS_KEY
   - VAULT_ADDR: https://vault.example.com:8200 (optional)
5. Click: "Run workflow" button
6. Monitor: Status updates in real-time
```

---

## CREDENTIAL REQUIREMENTS

### AWS Credentials (Required)
```
AWS_ACCESS_KEY_ID        : AKIA* (starts with AKIA, 20 chars)
REDACTED_AWS_SECRET_ACCESS_KEY: REDACTED_REDACTED_AWS_SECRET_ACCESS_KEY
Permissions Required     : IAM, KMS, OIDC (minimal: kms:Decrypt, iam:CreateRole, oidc:*)
```

### Vault Credentials (Optional)
```
VAULT_ADDR               : https://vault.example.com:8200
VAULT_NAMESPACE          : admin (or custom namespace)
JWT_TOKEN                : Service account JWT token (if JWT auth enabled)
Auth Method              : JWT (default) or LDAP
```

### GCP Credentials (Pre-configured)
```
Already configured via default application credentials
No additional input required
```

---

## EXECUTION WALKTHROUGH

### Step-by-Step (CLI Method - Recommended)

**Step 1: Navigate to repo**
```bash
cd /home/akushnir/self-hosted-runner
```

**Step 2: Verify setup**
```bash
ls -la scripts/phase3b-credential-manager.sh
# Expected: -rwxr-xr-x (executable)
```

**Step 3: Set AWS credentials**
```bash
./scripts/phase3b-credential-manager.sh set-aws \
  --key REDACTED_AWS_ACCESS_KEY_ID \
  --secret REDACTED_REDACTED_AWS_SECRET_ACCESS_KEY
# Expected: "✅ AWS credentials stored securely (~/.phase3b-credentials)"
```

**Step 4: Verify credentials (optional but recommended)**
```bash
./scripts/phase3b-credential-manager.sh verify
# Expected output:
# ✅ Layer 1 (GSM): Credentials available
# ✅ Layer 2A (Vault): Ready (awaiting Vault unsealing)
# ✅ Layer 2B (AWS KMS): Credentials valid
# ✅ Layer 3 (Cache): Prepared
```

**Step 5: Activate full deployment**
```bash
./scripts/phase3b-credential-manager.sh activate
# Expected: Deployment begins, watch immutable audit trail
```

**Step 6: Monitor deployment (in separate terminal)**
```bash
tail -f logs/deployment-provisioning-audit.jsonl | jq .
# Watch for: "phase3b_activation_complete" with status "success"
# Timeline: ~15 minutes to "✅ COMPLETE"
```

---

## POST-ACTIVATION VERIFICATION

### Immediate Verification (After Activation)
```bash
# Check activation status
./scripts/phase3b-credential-manager.sh verify

# Monitor progress
tail -20 logs/deployment-provisioning-audit.jsonl | jq '.[] | {timestamp, event, status}'
```

### 15-Minute Verification (After Phase 3B Completes)
```bash
# Verify AWS OIDC Provider created
aws iam list-open-id-connect-providers | jq '.OpenIDConnectProviderList[] | select(.Arn | contains("self-hosted-runner"))'
# Expected: ARN of OIDC provider

# Verify AWS KMS key created
aws kms describe-key --key-id phase3b-2026-03-09 | jq '.KeyMetadata.KeyId'
# Expected: ARN of KMS key

# Verify GitHub Secrets
gh secret list | grep -E "AWS|VAULT|KMS|PHASE"
# Expected: 15 secrets populated

# Verify Cloud Scheduler
gcloud scheduler jobs list | grep phase-3-credentials
# Expected: Job "phase-3-credentials-rotation" with frequency "*/15 * * * *"

# Verify Vault JWT (if unsealed)
vault list auth/jwt/role 2>/dev/null | grep self-hosted-runner || echo "Vault not yet unsealed"
# Expected: Vault JWT auth configured (if Vault available)
```

---

## EXPECTED TIMELINE

| Time | Activity | Status | Evidence |
|------|----------|--------|----------|
| T+0 sec | Admin executes activation command | 🔵 Running | Terminal output |
| T+30 sec | Credentials validated & stored | ✅ Complete | ~/. phase3b-credentials created (0600) |
| T+1 min | AWS OIDC Provider creation starts | 🔵 Running | Audit trail entry created |
| T+2 min | AWS KMS key provisioned | ✅ Complete | `aws kms describe-key` succeeds |
| T+3 min | Vault JWT auth configured | ✅ Complete | Vault policy updated |
| T+5 min | GitHub Actions secrets populated | ✅ Complete | `gh secret list` shows 15 secrets |
| T+8 min | Cloud Scheduler rotation job created | ✅ Complete | `gcloud scheduler jobs list` shows job |
| T+12 min | First credential rotation cycle completes | ✅ Complete | Audit trail shows rotation event |
| T+15 min | **DEPLOYMENT COMPLETE** | ✅ LIVE | Full system operational |

---

## EMERGENCY ROLLBACK

### If Something Goes Wrong During Activation
```bash
# STOP the current activation process
Ctrl+C

# Reset credential manager (safe - idempotent)
./scripts/phase3b-credential-manager.sh reset

# Rollback git commits (all operations safe)
git revert HEAD --no-edit

# Verify rollback
git log --oneline -3

# Re-activate after troubleshooting
# (see PHASE_3B_CREDENTIAL_INJECTION_GUIDE.md for troubleshooting)
```

### If Deployment Fails Mid-Way
```bash
# Re-run activation (all scripts are idempotent)
./scripts/phase3b-credential-manager.sh activate

# OR check what failed
tail -30 logs/deployment-provisioning-audit.jsonl | jq 'select(.status != "success")'

# Troubleshoot based on error
# See: docs/PHASE_3B_CREDENTIAL_INJECTION_GUIDE.md → Troubleshooting section
```

---

## IMPORTANT NOTES

### Security
- ✅ Use CLI method to avoid credentials in shell history  
- ✅ Credentials stored in ~/.phase3b-credentials (mode 0600, encrypted)  
- ✅ Never share credentials via email/chat  
- ✅ Credentials rotated automatically every 15 minutes after activation

### Compliance
- ✅ All operations logged to logs/deployment-provisioning-audit.jsonl  
- ✅ All commits immutable on main branch (git history preserved)  
- ✅ No manual intervention required after activation  
- ✅ All 7 architectural requirements maintained throughout

### Support
- **Questions about activation:** See PHASE_3B_CREDENTIAL_FRAMEWORK_READY_2026_03_09.md
- **Troubleshooting guide:** See docs/PHASE_3B_CREDENTIAL_INJECTION_GUIDE.md
- **Operations manual:** See PHASE_6_OPERATIONS_HANDOFF.md
- **Audit trail:** tail -f logs/deployment-provisioning-audit.jsonl | jq .

---

## FINAL CHECKLIST (Before Running)

- [ ] AWS_ACCESS_KEY_ID obtained from AWS account
- [ ] REDACTED_AWS_SECRET_ACCESS_KEY obtained from AWS account
- [ ] Current directory: /home/akushnir/self-hosted-runner
- [ ] Read: PHASE_3B_CREDENTIAL_FRAMEWORK_READY_2026_03_09.md
- [ ] Read: docs/PHASE_3B_CREDENTIAL_INJECTION_GUIDE.md
- [ ] Understand: Timeline & expected operations
- [ ] Understand: Rollback procedure (if needed)
- [ ] Ready to monitor: via `tail -f logs/deployment-provisioning-audit.jsonl | jq .`

---

## GO LIVE COMMAND

### Execute Once All Prerequisites Met
```bash
# Navigate
cd /home/akushnir/self-hosted-runner

# Set and activate credentials (choose one method)

# METHOD 1: CLI (Recommended)
./scripts/phase3b-credential-manager.sh set-aws --key REDACTED_AWS_ACCESS_KEY_ID --secret REDACTED_REDACTED_AWS_SECRET_ACCESS_KEY
./scripts/phase3b-credential-manager.sh activate

# OR METHOD 2: Environment
export AWS_ACCESS_KEY_ID=REDACTED_AWS_ACCESS_KEY_ID
export REDACTED_AWS_SECRET_ACCESS_KEY=REDACTED_REDACTED_AWS_SECRET_ACCESS_KEY
bash scripts/phase3b-credentials-inject-activate.sh

# OR METHOD 3: GitHub Actions
# Actions → "Phase 3B Credential Injection" → Run workflow
```

---

✅ **READY TO PROCEED** — Execute when credentials available.
