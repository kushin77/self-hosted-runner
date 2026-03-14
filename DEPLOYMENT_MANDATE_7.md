# DEPLOYMENT MANDATE #7: Automatic Fresh Build on Git Events

**MANDATE STATEMENT:**
On any commit/push to main branch or pull request merge, the entire stack shall automatically perform a complete fresh build deployment to the on-prem target host (192.168.168.42), with:
- ✅ Zero cloud operations
- ✅ Complete rebuild from source
- ✅ Fresh credentials generation
- ✅ Auto-rollback on failure
- ✅ Slack/GitHub notifications

---

## Summary

This mandate extends **Mandate #6 (Fresh Build Deployment)** by adding *automatic triggering* on Git events. When developers push code to main, there is zero delay—the entire stack automatically rebuilds fresh on the target host with full fresh build mandate enforcement.

**Key Principle:** "Ship and Watch" - developers push, the system automatically deploys, notifications appear.

---

## What Gets Automatically Deployed

1. **Trigger Events:**
   - Any commit pushed to `main` branch
   - Pull requests merged to `main`
   - Direct main branch pushes
   - Tag-based deployments (optional)

2. **Scope:**
   - Complete stack rebuild (all services, configs, credentials)
   - All 32+ service accounts
   - All 5 systemd services
   - All 2 automation timers
   - Fresh SSH keys generated
   - Previous state completely removed

3. **Target:**
   - Primary: 192.168.168.42 (on-prem worker)
   - Backup: Manual failover to 192.168.168.39 (if configured)
   - No cloud deployments under any circumstances

---

## Implementation Architecture

```
Developer Workflow     Git Server          Deployment System        Target Host
─────────────────────────────────────────────────────────────────────────────

git push main ────────→ receive refs ────────→ post-receive hook ──┐
                                               (server-side)         │
                                               │                     │
                                               └─→ launch trigger ───→ SSH connection
                                                                      ↓
                                                              git pull origin main
                                                                      ↓
                                                              /opt/.../deploy-worker-node.sh
                                                                      ↓
                                                              (4-phase fresh build)
                                                                      ↓
                                                         ┌─ SUCCESS ──→ verify services
                                                         │              notify Slack
                                                         │              update GitHub
                                                         │
                                                         └─ FAILURE ──→ auto-rollback
                                                                        restore backup
                                                                        notify ops team
```

---

## Enforcement Rules

### RULE: Automatic Trigger on Main
**Requirement:** Every push to `main` must trigger fresh build deployment

**Implementation:**
- Post-receive hook installed on Git server
- Post-push Git hook on developer machines
- Webhook receiver for external events (GitHub Actions, etc.)
- All three methods trigger the same deployment system

**Validation:**
```bash
# Verify post-receive hook exists
ls -la /path/to/repo.git/hooks/post-receive

# Verify post-push hook configured
git config core.hooksPath  # Should output: .githooks

# Check hook scripts are executable
ls -l .githooks/post-push
```

### RULE: No Manual Skipping Without Documentation
**Requirement:** Automatic deployments cannot be skipped without explicit override and documentation

**Implementation:**
```bash
# Normal - automatic deployment
git push origin main  # Triggers deployment immediately

# With override - requires environment marker
SKIP_DEPLOYMENT=true git push origin main  # Deployment skipped

# With dry-run - for testing
DRY_RUN=true git push origin main  # Shows what would deploy
```

**Audit:** All instances of `SKIP_DEPLOYMENT` or `DRY_RUN` are logged and audited

### RULE: Fresh Build Mandate Applies to Automatic Deployments
**Requirement:** Automatic deployment must follow complete Fresh Build Mandate

**Enforcement Points:**
```bash
# Pre-deployment validation (in post-push-deploy.sh)
1. verify_no_cloud_env()           # Block cloud credentials
2. verify_onprem_target()          # Enforce on-prem only
3. check_ssh_connectivity()        # Verify target reachable

# Deployment phase (deploy-worker-node.sh)
4. PHASE 1: Mandate validation     # Cloud prevention checks
5. PHASE 2: Clean slate            # Remove all previous state
6. PHASE 3: Fresh provision        # Rebuild from source
7. PHASE 4: Fresh credentials      # Generate new SSH keys

# Post-deployment verification
8. verify_deployment()             # Validate fresh build markers
9. verify_fresh_credentials()      # Confirm new keys deployed
10. verify_no_cloud_operations()   # Double-check no cloud access
```

### RULE: Auto-Rollback on Deployment Failure
**Requirement:** Failed deployments must automatically rollback to previous working state

**Implementation:**
```bash
# Before deployment - create backup
create_version_backup "$commit_sha"

# If deployment fails - use backup
rollback_to_version "$backup_path"

# If rollback fails - critical alert
notify_slack "failure: deployment failed AND rollback failed"
```

**Exclusions:** Rollback can be disabled with `SKIP_ROLLBACK=true` (requires explicit override)

### RULE: Status Notifications Required
**Requirement:** All deployments must send notifications to monitoring systems

**Channels:**
1. **Slack** - Real-time team notifications
   - ✅ `[SUCCESS]` Fresh build deployed
   - ❌ `[FAILED]` Deployment failed
   - ⚙️ `[ROLLBACK]` Auto-rollback executed

2. **GitHub** - Commit status updates
   - Pending: "Deployment in progress..."
   - Success: "✅ Fresh build deployment successful"
   - Failure: "❌ Fresh build deployment failed"

3. **Logs** - Comprehensive audit trail
   - Deployment logs: `logs/deployments/YYYYMMDD_HHMMSS.log`
   - Version backups: `.deployment-backups/`
   - Status markers: `.last-deployment` JSON

---

## Deployment Trigger System Config

### Installation

```bash
# Full setup (developers and operators)
bash scripts/triggers/install.sh

# Developers only
bash scripts/triggers/install.sh --local-only

# Operators only
bash scripts/triggers/install.sh --remote-setup

# Verification
bash scripts/triggers/install.sh verify
```

### Configuration File

**Location:** `.deployment.env` (local, not committed)

```bash
# Deployment targets
export TARGET_HOST=192.168.168.42
export SERVICE_ACCOUNT=automation
export SSH_KEY=~/.ssh/automation_ed25519

# Notifications (optional)
export SLACK_WEBHOOK="https://hooks.slack.com/services/..."
export GITHUB_TOKEN="ghp_..."

# Behavior controls
export DETECTION_STRATEGY=full    # full|smart|tags
export DRY_RUN=false
export SKIP_ROLLBACK=false
```

### Environment Setup

```bash
# Generate SSH key
ssh-keygen -t ed25519 -f ~/.ssh/automation_ed25519 -N ""

# Authorize on target
ssh-copy-id -i ~/.ssh/automation_ed25519 automation@192.168.168.42

# Test connectivity
ssh -i ~/.ssh/automation_ed25519 automation@192.168.168.42 "echo OK"

# Create .deployment.env
cat > .deployment.env <<'EOF'
export TARGET_HOST=192.168.168.42
export SERVICE_ACCOUNT=automation
export SSH_KEY=~/.ssh/automation_ed25519
EOF

# Add to gitignore
echo ".deployment.env" >> .gitignore
```

---

## Component Selection Strategies

### Strategy 1: FULL (Default)
```bash
DETECTION_STRATEGY=full git push origin main

Behavior: Always rebuild entire stack
Reason: Maximum safety, no smart detection logic
Best for: Production, when in doubt
```

### Strategy 2: SMART
```bash
DETECTION_STRATEGY=smart git push origin main

Behavior: Analyze changed files, rebuild affected components
Examples:
  - Changes to deploy scripts → full rebuild
  - Changes to auth service → rebuild auth + dependencies
  - Changes to docs only → skip deployment
  - Changes to configs → rebuild core services

Best for: Large monorepos with independent services
```

### Strategy 3: TAGS
```bash
git commit -m "Fix auth service [DEPLOY:auth,api]"
git push origin main

Behavior: Use commit message tags to specify components
Examples:
  [DEPLOY:full]             → full rebuild
  [DEPLOY:auth]             → rebuild auth + deps
  [DEPLOY:auth,api,core]    → rebuild specified
  [DEPLOY:skip-deploy]      → skip deployment

Best for: Developers who know exactly what changed
```

---

## Operational Procedures

### First-Time Setup (Developer)
```bash
# 1. Clone repository
git clone https://github.com/kushin77/self-hosted-runner.git
cd self-hosted-runner

# 2. Install triggers
bash scripts/triggers/install.sh --local-only

# 3. Create SSH key
ssh-keygen -t ed25519 -f ~/.ssh/automation_ed25519

# 4. Configure
cat > .deployment.env <<EOF
export TARGET_HOST=192.168.168.42
export SERVICE_ACCOUNT=automation
export SSH_KEY=~/.ssh/automation_ed25519
EOF

# 5. Test
bash scripts/triggers/install.sh verify

# 6. First deployment
git push origin main  # Automatic fresh build triggered!
```

### Daily Development (Push & Watch)
```bash
# Make changes
vim src/services/auth.js
git add src/services/auth.js
git commit -m "Fix authentication bug"

# Push to trigger automatic deployment
git push origin main

# Watch deployment in real-time
tail -f logs/deployments/$(date +%Y%m%d)_*.log

# Slack notification arrives (success/failure)
# GitHub commit status updated
# Done!
```

### Handling Deployment Failure
```bash
# Automatic rollback happens in background
# Slack notification: "⚙️ Auto-Rollback Triggered"

# Check what failed
cat logs/deployments/YYYYMMDD_HHMMSS.log

# Investigate and fix
# Then push fix
git push origin main  # Fresh deployment with fix
```

### Manual Rollback
```bash
# Find backup to restore
ls -la .deployment-backups/

# Check metadata
cat .deployment-backups/backup-ABC123-*/metadata

# Rollback manually (if auto-rollback didn't work)
ssh automation@192.168.168.42
cd /opt/self-hosted-runner
git checkout <backup-sha>
bash deploy-worker-node.sh
exit
```

---

## Monitoring & Logs

### Real-Time Monitoring
```bash
# Watch current deployment
tail -f logs/deployments/$(date +%Y%m%d)_*.log

# Check Slack for notifications
# (appear within seconds of deployment completion)

# Monitor GitHub commit status
# (updated in real-time during deployment)
```

### Historical Analysis
```bash
# Last deployment status
cat .last-deployment | jq .

# Recent deployment logs
ls -lt logs/deployments/ | head -10

# Version backup history
ls -lt .deployment-backups/ | head -10

# Search for specific commit
grep -r "abc123def456" logs/deployments/
```

### Metrics
```bash
# Count successful deployments
ls .deployment-backups/ | wc -l

# Average deployment time
jq .duration_seconds .last-deployment

# Rollback frequency
grep -l "rollback" logs/deployments/* | wc -l
```

---

## Integration with Fresh Build Mandate

This mandate reinforces **Mandate #6 (Fresh Build Deployment)** by:

1. **Enforcing Frequency:**
   - Fresh build happens on every main push
   - No stale deployments or manual steps
   - Consistent timing and procedures

2. **Ensuring Completeness:**
   - Full stack always rebuilt
   - Every dependency verified fresh
   - Zero stale component risk

3. **Validating Compliance:**
   - Mandate checks run before trigger
   - On-prem validation before deployment
   - Cloud prevention always enforced

4. **Providing Audit Trail:**
   - Git history of all deployments
   - Version backups for all states
   - Comprehensive notification logs

5. **Enabling Fast Recovery:**
   - Auto-rollback on any failure
   - Backup available for every deployment
   - Manual recovery procedures documented

---

## Commit Message Guidelines

Use these patterns in commit messages to control deployments:

```bash
# Default - full rebuild (no tag needed)
git commit -m "Fix auth service"

# Explicit full rebuild
git commit -m "Major refactor [DEPLOY:full]"

# Specific components
git commit -m "Update API and core [DEPLOY:api,core]"

# Multiple services
git commit -m "Monitoring stack update [DEPLOY:monitoring,timers,core]"

# Skip deployment (requires override)
git commit -m "Doc update - no deploy [DEPLOY:skip]"
# Then: SKIP_DEPLOYMENT=true git push

# Dry-run test
# Then: DRY_RUN=true git push
```

---

## Troubleshooting Common Issues

### "Post-push hook not triggering deployment"
```bash
# Check hooks are installed
git config core.hooksPath  # Should be: .githooks

# Check hook is executable
ls -l .githooks/post-push  # Should have -rwx

# Reinstall
bash scripts/triggers/install.sh --local-only
```

### "SSH connection refused"
```bash
# Verify SSH key exists
ls -la ~/.ssh/automation_ed25519

# Check key permissions
chmod 600 ~/.ssh/automation_ed25519
chmod 700 ~/.ssh

# Test connectivity
ssh -vvv -i ~/.ssh/automation_ed25519 automation@192.168.168.42

# Add to .deployment.env if non-standard location
export SSH_KEY=/custom/path/to/key
```

### "Deployment succeeds but services don't start"
```bash
# SSH to target
ssh automation@192.168.168.42

# Check deployment log
cat /opt/self-hosted-runner/logs/deployments/latest.log

# Verify fresh build completed
bash /opt/self-hosted-runner/scripts/enforce/verify-fresh-build-deployment.sh

# Check systemd services
systemctl status monitoring-* alert-triage.timer
```

### "Auto-rollback failed"
```bash
# CRITICAL! Manual intervention required

# SSH to target immediately
ssh automation@192.168.168.42

# Check git status
cd /opt/self-hosted-runner
git status
git log --oneline -5

# Manual recovery
git checkout <previous-working-sha>
bash deploy-worker-node.sh

# Verify status
bash scripts/enforce/verify-fresh-build-deployment.sh

# Notify team
# (don't return to normal until fully recovered)
```

---

## Security Requirements

1. **SSH Key Management**
   - Use Ed25519 keys only
   - Rotate annually
   - Separate deploy key from user key
   - Store with 600 permissions

2. **Webhook Security**
   - HMAC-SHA256 signature validation
   - Rotate secrets quarterly
   - Log all webhook attempts
   - Monitor failed validations

3. **Access Control**
   - Only main branch pushes trigger deploys
   - PR reviews required before merge to main
   - Signed commits recommended
   - GitHub branch protection rules active

4. **Notification Security**
   - Slack webhooks scoped to specific channels
   - GitHub tokens with minimal scopes
   - Avoid sending credentials in notifications
   - Rotate tokens quarterly

---

## Change History

**Version:** 1.0 (March 14, 2026)
- Initial implementation of automated deployment triggers
- Full integration with Fresh Build Mandate
- Auto-rollback capability
- Slack and GitHub notifications

---

## Related Documentation

- [Fresh Build Deployment Mandate (#6)](ENFORCEMENT_RULES.md#rule-6-fresh-build-deployment)
- [Automated Deployment Triggers](AUTOMATED_DEPLOYMENT_TRIGGERS.md)
- [Deployment Instructions](DEPLOYMENT_INSTRUCTIONS.md)
- [Code Mandates](CODE_MANDATES.md)

