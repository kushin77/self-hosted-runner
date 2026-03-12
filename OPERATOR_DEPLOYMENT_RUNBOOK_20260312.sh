#!/bin/bash
# OPERATOR DEPLOYMENT RUNBOOK — March 12, 2026
# This document guides operators through final deployment steps for milestone-2 remediation

set -euo pipefail

cat <<'EOF'
╔════════════════════════════════════════════════════════════════════════════╗
║                         OPERATOR DEPLOYMENT RUNBOOK                         ║
║                   Milestone-2 Autonomous Deployment Phase                   ║
║                         March 12, 2026 — Final Steps                         ║
╚════════════════════════════════════════════════════════════════════════════╝

This runbook guides you through 3 final operator actions:
  1. Merge PRs #2838 & #2840 (code review approval)
  2. Deploy runner SSH public key to all runner hosts
  3. Verify branch protections

Expected Duration: ~30 minutes (parallel execution possible)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

STEP 1: MERGE PULL REQUESTS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Purpose: Deploy normalizer CronJob image updates and runner key distribution script

Action 1.1: Merge PR #2838 (CronJob image update)
──────────────────────────────────────────────────
URL: https://github.com/kushin77/self-hosted-runner/pull/2838

Steps:
  a) Review PR (should show 2 file changes: k8s/ and nexus-engine/k8s/)
  b) Approve (if using GitHub's review feature)
  c) Merge with default strategy (squash or merge, no ff)

Commands:
  gh pr view 2838 --repo kushin77/self-hosted-runner
  gh pr merge 2838 --repo kushin77/self-hosted-runner --merge

Expected: ✓ Merged (Cloud Build will auto-target this commit if configured)

Action 1.2: Merge PR #2840 (runner key deployment script)
──────────────────────────────────────────────────────────
URL: https://github.com/kushin77/self-hosted-runner/pull/2840

Steps:
  a) Review PR (should add scripts/ops/deploy-runner-ssh-key.sh)
  b) Approve
  c) Merge

Commands:
  gh pr view 2840 --repo kushin77/self-hosted-runner
  gh pr merge 2840 --repo kushin77/self-hosted-runner --merge

Expected: ✓ Merged; script available on main

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

STEP 2: DEPLOY RUNNER SSH PUBLIC KEY TO HOSTS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Purpose: Rotate SSH keys on all runner fleet (no more committed keys in repo)

Prerequisites:
  ✓ GSM secret runner-ssh-key-20260312194327 exists (created 2026-03-12 19:43:27Z)
  ✓ Operator has SSH access to all runner hosts (or can sudo to root)
  ✓ GCP service account has GSM access (nxs-automation-sa@nexusshield-prod.iam.gserviceaccount.com)

Action 2.1: Prepare runner host list
────────────────────────────────────
Identify all self-hosted runner hosts you need to update.

Examples:
  Single runner:    "runner1.internal"
  Multiple runners: "runner1.internal,runner2.internal,runner3.internal"
  IP addresses:     "192.168.168.42,192.168.168.43,192.168.168.44"

If runners are in different subnets, you may deploy in parallel batches:
  Batch 1: RUNNER_HOSTS="internal1,internal2" <deploy-script>
  Batch 2: RUNNER_HOSTS="external1,external2" <deploy-script>

Action 2.2: Execute deployment
───────────────────────────────
Once PRs are merged, pull latest and run the deployment script:

  cd ~/self-hosted-runner
  git pull origin main
  
  # Option A: Batch deployment (recommended)
  RUNNER_HOSTS="host1,host2,host3" \\
    ./scripts/ops/deploy-runner-ssh-key.sh \\
    --project=nexusshield-prod \\
    --secret-name=runner-ssh-key-20260312194327 \\
    --user=root \\
    --port=22

  # Option B: Single host
  ./scripts/ops/deploy-runner-ssh-key.sh \\
    --project=nexusshield-prod \\
    --secret-name=runner-ssh-key-20260312194327 \\
    --user=root \\
    --hosts=runner1.internal

Expected output:
  📥 Fetching runner-ssh-key-20260312194327 from GSM (project: nexusshield-prod)
  🔑 Deriving public key
  ✅ Public key: ssh-ed25519 AAAAC3... (truncated)
  🚀 Deploying to root@runner1.internal:22
  ✅ Key deployed to runner1.internal
  [... repeat for each host ...]
  ✅ Deployment complete. Runners can now authenticate using the rotated SSH key.

Action 2.3: Verify SSH connectivity (post-deployment)
──────────────────────────────────────────────────────
Test one host to confirm new key works:

  # If you have the private key locally (not recommended):
  ssh -i /path/to/runner-key root@runner1.internal "echo 'SSH works!'"

  # More likely: GSM fetches the key at runtime
  gcloud secrets versions access latest --secret=runner-ssh-key-20260312194327 \\
    --project=nexusshield-prod > /tmp/runner_key.pem
  chmod 600 /tmp/runner_key.pem
  ssh -i /tmp/runner_key.pem root@runner1.internal "echo 'SSH works!'"

  rm /tmp/runner_key.pem

Expected: ✓ SSH works! (can log in without password prompt for existing SSH key)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

STEP 3: VERIFY BRANCH PROTECTIONS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Purpose: Confirm that main and production branches are protected

Action 3.1: Check current protections
──────────────────────────────────────
Run:
  gh api repos/kushin77/self-hosted-runner/branches/main/protection --jq .
  gh api repos/kushin77/self-hosted-runner/branches/production/protection --jq .

If you get a 404 error ("Branch not protected"):
  → Protections may have been cleared during history rewrite. See Step 3.3.

Action 3.2: Expected protection rules
───────────────────────────────────────
**main branch:**
  - No required status checks (development branch, fast-merge allowed)
  - No required PR reviews
  - Force pushes disabled
  - Branch deletion disabled

**production branch:**
  - Required status checks: "validate-policies-and-keda" (strict mode)
  - Require 1 PR review + dismiss stale reviews
  - Enforce for admins: YES
  - Force pushes disabled
  - Branch deletion disabled

Action 3.3: Re-apply protections (if missing)
───────────────────────────────────────────────
If check failed, you'll need an org admin token with repo:admin scope:

  # Set token (org admin only)
  export GH_TOKEN="<org-admin-token>"

  # Re-apply production protection
  gh api -X PUT repos/kushin77/self-hosted-runner/branches/production/protection \\
    -f required_status_checks='{"strict":true,"contexts":["validate-policies-and-keda"]}' \\
    -f enforce_admins=true \\
    -f required_pull_request_reviews='{"dismiss_stale_reviews":true,"require_code_owner_reviews":false,"required_approving_review_count":1}'

  # Re-apply main protection (minimal)
  gh api -X PUT repos/kushin77/self-hosted-runner/branches/main/protection \\
    -f required_status_checks=null \\
    -f enforce_admins=false

Expected: ✓ Protections reapplied

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

SIGN-OFF CHECKLIST
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Before declaring milestone-2 complete:

  [ ] PR #2838 merged (CronJob + image tag updated)
  [ ] PR #2840 merged (runner deployment script available)
  [ ] Runner SSH public key deployed to all hosts
  [ ] SSH login test successful (at least 1 host verification)
  [ ] Branch protections verified (main + production)
  [ ] Artifact uploaded to GCS (audit-trail.jsonl with 365-day retention)
  [ ] No new credential findings in pre-commit scans
  [ ] All 8 governance gates still passing

Once complete, update issue tracking:
  ✅ Close: #2747 (normalizer image)
  ✅ Close: #2749 (normalizer image)
  ✅ Comment on: #2216 (admin-blocked items) with summary

Expected Timeline:
  Step 1 (merge):     ~5 min
  Step 2 (deploy):    ~10–15 min (parallel safe)
  Step 3 (verify):    ~5 min
  ───────────────────
  Total:              ~20–25 min

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

TROUBLESHOOTING
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Q: Deployment script fails with "Could not create .ssh on host"
A: Check SSH connectivity and user permissions. If using non-root:
   - User must have home directory ($HOME is writable)
   - May need `sudo mkdir -p ~/.ssh && sudo chmod 700 ~/.ssh`

Q: "Key already authorized" message — is that OK?
A: Yes! Idempotent behavior. Key is already in authorized_keys; no change needed.

Q: How do I verify the key was deployed?
A: Log in with:
   ssh -i <private> root@<host> "grep -c 'ssh-ed25519' ~/.ssh/authorized_keys"
   Should output: 1 (at least)

Q: Can I deploy to multiple hosts in parallel?
A: Yes. You can use xargs, GNU parallel, or simple backgrounding:
   echo "host1 host2 host3" | xargs -P 3 -I{} bash -c \
     'RUNNER_HOSTS={} ./scripts/ops/deploy-runner-ssh-key.sh ...'

Q: What if I deploy to the wrong host by accident?
A: The script is idempotent and only appends to authorized_keys. You can:
   1. Re-run the script (no harm)
   2. Manually remove the key: ssh root@host 'sed -i "/<pubkey>/d" ~/.ssh/authorized_keys'

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Document Version: 1.0
Generated: 2026-03-12 20:45 UTC
Next Review: After all steps complete

For questions or blockers, contact: @kushin77 @BestGaaS220
EOF
