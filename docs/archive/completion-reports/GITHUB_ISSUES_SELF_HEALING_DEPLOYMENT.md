# GitHub Issues - Self-Healing Infrastructure Deployment Tracking

## Issue #1: Phase 1 - Merge Infrastructure to Main

**Title:** Phase 1: Merge self-healing infrastructure to main branch

**Labels:** automation, security, p0, self-healing

**Assignee:** akushnir

**Body:**
```
Merge PR with multi-layer self-healing orchestration system (13 files, 2,200+ LOC).

**Status:** Files created and committed, ready for PR creation

**Components:**
- Compliance auto-fixer (Python 400+ lines, daily 00:00 UTC)
- Secrets rotation (350+ lines, daily 03:00 UTC, multi-layer)
- Dynamic secret retrieval (3 actions, OIDC/WIF/JWT)
- OIDC/WIF setup (4 idempotent scripts)
- Key revocation (300+ lines, multi-layer)

**Acceptance Criteria:**
- [ ] PR created and reviewed
- [ ] Code review completed
- [ ] Merge to main branch (squash-merge recommended)
- [ ] Workflows activate in production
- [ ] Verify first scheduled runs (00:00 UTC compliance scan)

**Next Step:** Proceed to Phase 2 (OIDC/WIF setup)
**Blocking:** Phase 2 cannot start until Phase 1 completes
**Estimated Time:** 2-4 hours for review + merge
```

---

## Issue #2: Phase 2 - Setup OIDC/WIF Infrastructure

**Title:** Phase 2: Setup OIDC/WIF for GCP, AWS, and Vault JWT

**Labels:** automation, security, p0, infrastructure, self-healing

**Assignee:** akushnir

**Body:**
```
Setup Workload Identity Federation and OIDC providers across GCP, AWS, and Vault.

**Prerequisites:**
- [ ] Phase 1 merged to main
- [ ] GCP credentials (gcloud CLI authenticated)
- [ ] AWS credentials (aws CLI authenticated)
- [ ] Vault admin token (in VAULT_ADMIN_TOKEN secret)
- [ ] Project IDs/Account IDs collected

**Execution:**
1. Collect required parameters:
   - GCP_PROJECT_ID (your GCP project)
   - AWS_ACCOUNT_ID (your AWS account number)
   - VAULT_ADDR (your Vault server HTTPS address)

2. Trigger setup workflow:
   \`\`\`bash
   gh workflow run setup-oidc-infrastructure.yml \
     -f gcp-project-id="YOUR-PROJECT" \
     -f aws-account-id="123456789012" \
     -f vault-addr="https://vault.example.com" \
     -f dry-run="false"
   \`\`\`

3. Collect outputs from workflow artifacts:
   - gcp-provider.txt → GCP_WORKLOAD_IDENTITY_PROVIDER
   - gcp-sa-email.txt → GCP_SERVICE_ACCOUNT
   - aws-role-arn.txt → AWS_ROLE_TO_ASSUME
   - aws-provider-arn.txt → AWS_OIDC_PROVIDER
   - vault-addr.txt → VAULT_ADDR

4. Update GitHub repository secrets:
   \`\`\`bash
   gh secret set GCP_WORKLOAD_IDENTITY_PROVIDER --body "..."
   gh secret set GCP_SERVICE_ACCOUNT --body "..."
   gh secret set GCP_PROJECT_ID --body "..."
   gh secret set AWS_ROLE_TO_ASSUME --body "..."
   gh secret set AWS_OIDC_PROVIDER --body "..."
   gh secret set VAULT_ADDR --body "..."
   \`\`\`

**Acceptance Criteria:**
- [ ] Workflow executed successfully
- [ ] All 4 secrets configured in repository
- [ ] Test secret retrieval from each provider:
  \`\`\`bash
  gh workflow run compliance-auto-fixer.yml  # Test GSM retrieval
  gh workflow run rotate-secrets.yml         # Test Vault + AWS retrieval
  \`\`\`
- [ ] All tests pass (review audit trails)

**Next Step:** Proceed to Phase 3 (Key revocation)
**Blocked By:** Phase 1
**Duration:** 30-60 minutes (setup + verification)
```

---

## Issue #3: Phase 3 - Rotate/Revoke Exposed Keys

**Title:** Phase 3: Rotate and revoke exposed/compromised keys

**Labels:** security, remediation, p1, self-healing

**Assignee:** akushnir

**Body:**
```
Identify and revoke any compromised credentials across GCP, AWS, and Vault.

**Prerequisites:**
- [ ] Phase 2 completed (OIDC/WIF configured)
- [ ] Exposed key inventory prepared (use git-secrets scan)
- [ ] Understand impact of revoking each key

**Step 1: Inventory Exposed Keys**
\`\`\`bash
# Scan repository history for potential secrets
git log --all -p -S 'password\\|secret\\|token\\|key' --grep='.' | head -500

# Use git-secrets
git clone https://github.com/awslabs/git-secrets.git
cd git-secrets && make install
git secrets --scan-history --all
\`\`\`

**Step 2: Test Revocation (Dry-Run)**
\`\`\`bash
# Safe test - shows what would be revoked without making changes
gh workflow run revoke-keys.yml \
  -f dry-run="true" \
  -f exposed-key-ids="KEY1,KEY2,KEY3"
\`\`\`

Review dry-run output and audit trail.

**Step 3: Execute Revocation (if keys found)**
\`\`\`bash
# Actual revocation
gh workflow run revoke-keys.yml \
  -f dry-run="false" \
  -f exposed-key-ids="KEY1,KEY2,KEY3"
\`\`\`

**Step 4: Validate No Secrets Remain**
- [ ] Review git-secrets scan results (should be clean)
- [ ] Check audit trail: .key-rotation-audit/key-revocation-audit.jsonl
- [ ] Verify all keys were revoked successfully

**Step 5: Create Replacement Keys**
For each revoked key in GCP, AWS, Vault:
1. Create new key in provider
2. Update workflows/applications to use new keys (via rotate-secrets.yml)
3. Test connectivity with new keys
4. Document in incident post-mortem

**Acceptance Criteria:**
- [ ] All exposed keys identified
- [ ] Revocation tested in dry-run
- [ ] Actual revocation executed
- [ ] Validation: no secrets remain
- [ ] Replacement keys created
- [ ] All applications updated + tested

**Notes:**
- KMS/Vault keys auto-rotate daily after this point
- No manual key management needed going forward
- Audit trails preserved for compliance

**Blocked By:** Phase 2
**Duration:** 1-2 hours per batch of keys
```

---

## Issue #4: Phase 4 - Production Deployment Validation

**Title:** Phase 4: Validate production workflows and audit trails

**Labels:** automation, testing, self-healing

**Assignee:** akushnir

**Body:**
```
Validate that all scheduled workflows are executing correctly in production.

**Prerequisites:**
- [ ] Phase 3 completed (key revocation)
- [ ] All GitHub secrets configured
- [ ] Repository has been on main for 24+ hours

**Daily Checks:**
Verify workflows are running at scheduled times:
- Compliance auto-fixer: Daily 00:00 UTC
- Secrets rotation: Daily 03:00 UTC

Check GitHub Actions > All Workflows:
\`\`\`bash
gh workflow list

# Check recent runs
gh run list --workflow=compliance-auto-fixer.yml --limit=5
gh run list --workflow=rotate-secrets.yml --limit=5
\`\`\`

**Validation Checklist:**

□ Compliance Auto-Fixer
  - [ ] Runs at 00:00 UTC daily
  - [ ] Scans all workflows
  - [ ] No critical errors in logs
  - [ ] Audit trail growing: .compliance-audit/*.jsonl

□ Secrets Rotation
  - [ ] Runs at 03:00 UTC daily
  - [ ] All 3 providers (GSM, Vault, AWS) complete
  - [ ] No credential retrieval failures
  - [ ] Audit trail: .credentials-audit/rotation-audit.jsonl

□ Audit Artifacts
  - [ ] Artifacts uploaded (365-day retention)
  - [ ] No secrets exposed in logs
  - [ ] Timestamps and actions logged
  - [ ] Can export for compliance review

**Weekly Review:**
\`\`\`bash
# Count audit events this week
find . -name "*audit*.jsonl" -type f -exec wc -l {} +

# Check for any failures
gh run list --workflow=compliance-auto-fixer.yml --limit=100 | grep -i failed
gh run list --workflow=rotate-secrets.yml --limit=100 | grep -i failed
\`\`\`

**Escalation Procedure:**
If >3 failures in any 24-hour period:
1. Check artifact logs for root cause
2. Verify GitHub secrets are still valid
3. Check provider status pages (GCP, AWS, Vault)
4. Create incident issue if needed

**Acceptance Criteria:**
- [ ] All workflows executing on schedule
- [ ] Success rate >99%
- [ ] Audit trails accumulating normally
- [ ] No credential failures
- [ ] Ready for full production use

**Next Step:** Transition to ongoing monitoring
**Duration:** Continuous (1-2 weeks verification)
```

---

## Issue #5: Phase 5 - First-Week Monitoring & Daily Reports

**Title:** Phase 5: First-week monitoring and incident response setup

**Labels:** automation, monitoring, self-healing

**Assignee:** akushnir

**Body:**
```
Establish ongoing monitoring and create incident response procedures.

**Daily Monitoring (7 Days):**

Each morning, check:
\`\`\`bash
# Review yesterday's runs
gh run list --created='today-1..today' --workflow=compliance-auto-fixer.yml
gh run list --created='today-1..today' --workflow=rotate-secrets.yml

# Count audit events
echo "Compliance audit entries:"
wc -l .compliance-audit/*-$(date -d yesterday +%s).jsonl

echo "Rotation audit entries:"
tail -100 .credentials-audit/rotation-audit.jsonl

# Check for any failures
gh run list --status=failed --limit=20
\`\`\`

**Report Template (Daily):**
- [ ] Compliance scan: PASS/FAIL (X violations found, Y auto-fixed)
- [ ] Secrets rotation: PASS/FAIL (3/3 providers successful)
- [ ] Audit trail: Growing normally (X new entries)
- [ ] No credential failures
- [ ] No exposed secrets detected
- [ ] All scheduled runs completed

**Incident Response:**

If a workflow fails:
1. Check artifact logs for error message
2. Review corresponding audit trail
3. Verify GitHub secrets haven't been modified
4. Check provider status (GCP/AWS/Vault status pages)
5. Create incident issue if external factor

If secrets are detected:
1. Immediately trigger revoke-keys.yml with dry-run=true
2. Review what would be revoked
3. Execute actual revocation
4. Create incident post-mortem
5. Identify how secret was exposed

**Escalation Matrix:**
- 1 failure in 24h → Monitor, no action needed
- 3 failures in 24h → Create incident issue, investigate
- Any secret exposure → Immediate revocation + incident

**Integration with Existing Processes:**
- Link daily reports to project management system
- Include in weekly status meetings
- Export audit trails for compliance/auditing
- Archive successful runs (30-day retention minimum)

**Acceptance Criteria:**
- [ ] Daily monitoring established
- [ ] Report template created
- [ ] Incident escalation procedure documented
- [ ] Team trained on incident response
- [ ] Ready for 24/7 operations

**Success Metrics (After 7 Days):**
- Workflow success rate: >99%
- Mean time to revoke compromised keys: <1 hour
- Audit trail completeness: 100%
- No false positives in compliance scanning
- Zero credential exposure incidents

**Next Steps:**
- [ ] Transition to weekly reports
- [ ] Monitor ongoing compliance
- [ ] Plan quarterly training
- [ ] Extend to other repositories
```

---

## Creating These Issues

Run these commands in sequence (or create PR with this document for team review):

```bash
# Issue 1: Phase 1
gh issue create --title "Phase 1: Merge self-healing infrastructure to main branch" \
  --body "$(sed -n '/^## Issue #1/,/^## Issue #2/p' GITHUB_ISSUES.md | head -30)" \
  --assignee akushnir --label automation,security,p0

# Issue 2: Phase 2
gh issue create --title "Phase 2: Setup OIDC/WIF for GCP, AWS, and Vault JWT" \
  --body "..." \
  --assignee akushnir --label automation,security,p0,infrastructure

# Issue 3: Phase 3
gh issue create --title "Phase 3: Rotate and revoke exposed/compromised keys" \
  --body "..." \
  --assignee akushnir --label security,remediation,p1

# Issue 4: Phase 4
gh issue create --title "Phase 4: Validate production workflows and audit trails" \
  --body "..." \
  --assignee akushnir --label automation,testing

# Issue 5: Phase 5
gh issue create --title "Phase 5: First-week monitoring and incident response setup" \
  --body "..." \
  --assignee akushnir --label automation,monitoring

# Or create parent epic issue linking all phases
gh issue create --title "[EPIC] Self-Healing Infrastructure Deployment" \
  --body "Complete multi-phase deployment of immutable, ephemeral, idempotent self-healing system with zero long-lived credentials. See Phase 1, 2, 3, 4, 5 issues for detailed requirements and acceptance criteria." \
  --assignee akushnir --label epic,automation,security,p0
```

---

## Deployment Progress Checklist

- [x] Phase 0: Create all infrastructure files (13 files, 2,200+ LOC)
- [ ] Phase 1: Create PR, review, and merge to main
- [ ] Phase 2: Execute OIDC/WIF setup (30-60 min)
- [ ] Phase 3: Identify and revoke exposed keys (1-2 hours)
- [ ] Phase 4: Validate production workflows (1-2 weeks)
- [ ] Phase 5: Establish ongoing monitoring (7 days)

**Total Estimated Time:** 2-3 weeks for full production deployment

---

**Document Created:** 2026-03-08
**Status:** Ready for issue creation
