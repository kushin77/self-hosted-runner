# 🚀 Automated Deployment Trigger System

## MANDATE: Automatic Fresh Build on Git Events

**On any commit/push to main branch → Automatic complete fresh build deployment to 192.168.168.42**

This system provides fully automated fresh build deployments following the mandate:
- ✅ Complete fresh build (no incremental updates)
- ✅ Triggered automatically on main branch push/merge
- ✅ Full stack rebuild on every change
- ✅ Auto-rollback on deployment failure
- ✅ Slack notifications on success/failure
- ✅ GitHub status updates

---

## System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Developer Workflow                       │
├─────────────────────────────────────────────────────────────┤
│
│   git push origin main
│        ↓
│   ┌─────────────────────────────────────────────┐
│   │  GitHub Repository (Remote)                  │
│   │  - Push received                             │
│   │  - post-receive hook triggered              │
│   └──────────────────┬──────────────────────────┘
│                      ↓
│   ┌─────────────────────────────────────────────┐
│   │  Post-Receive Hook (Server-Side)            │
│   │  - Detects main branch push                 │
│   │  - Launches deployment trigger              │
│   └──────────────────┬──────────────────────────┘
│                      ↓
│   ┌─────────────────────────────────────────────┐
│   │  Deployment Trigger System                   │
│   │  (post-push-deploy.sh)                      │
│   │  - Validates SSH connectivity               │
│   │  - Syncs code to target host                │
│   │  - Executes fresh build deployment          │
│   │  - Monitors deployment status               │
│   │  - Auto-rollback on failure                 │
│   └──────────────────┬──────────────────────────┘
│                      ↓
│   ┌─────────────────────────────────────────────┐
│   │  Target Host (192.168.168.42)               │
│   │  - Receives code update (git pull)          │
│   │  - Executes deploy-worker-node.sh           │
│   │  - Complete fresh build with mandate checks │
│   │  - Enforces on-prem only deployment         │
│   │  - Verifies fresh credentials               │
│   │  - Creates version backup                   │
│   └──────────────────┬──────────────────────────┘
│                      ↓
│   ┌─────────────────────────────────────────────┐
│   │  Notifications & Status Updates             │
│   │  - Slack: SUCCESS/FAILURE/ROLLBACK          │
│   │  - GitHub: commit status updated            │
│   │  - Logs: comprehensive audit trail          │
│   └─────────────────────────────────────────────┘
```

---

## Components

### 1. Local Git Hooks
**Location:** `.githooks/`

#### pre-push Hook
- Validates code before push
- Security scanning
- Deployment readiness check
- Prevents pushing broken code

#### post-push Hook
- Triggered after successful push to main
- Calls deployment trigger script
- Provides immediate feedback to developer
- Runs deployment in background

### 2. Post-Receive Hook (Server-Side)
**Location:** `scripts/triggers/post-receive-hook.sh`

Installed on remote Git server (or 192.168.168.42):
- Runs when commits arrive on server
- Detects main branch pushes
- Launches deployment asynchronously
- Provides acknowledgment to git client

### 3. Deployment Trigger
**Location:** `scripts/triggers/post-push-deploy.sh` (14K, 320+ lines)

Main orchestrator for automatic deployments:
- Validates SSH connectivity
- Creates version backup
- Syncs latest code to target
- Executes fresh build via deploy-worker-node.sh
- Monitors deployment progress
- Auto-rollback on failure
- Slack notifications

**Environment Variables:**
```bash
TARGET_HOST=192.168.168.42          # Deployment target
SERVICE_ACCOUNT=automation          # SSH account
SSH_KEY=~/.ssh/automation_ed25519  # SSH key
SLACK_WEBHOOK=https://...          # Slack webhook (optional)
DRY_RUN=false                       # Preview mode
SKIP_ROLLBACK=false                # Auto-rollback enabled
```

### 4. Component Detection
**Location:** `scripts/triggers/detect-component-changes.sh` (9.6K)

Analyzes what changed and decides what to rebuild:

**Strategies:**
1. **FULL** (default): Rebuild entire stack always
2. **SMART**: Analyze changed files, rebuild only affected components
3. **TAGS**: Use commit message tags like `[DEPLOY:auth,api]`

**Example Usage:**
```bash
# Full rebuild (safest)
DETECTION_STRATEGY=full git push origin main

# Smart detection
DETECTION_STRATEGY=smart GITHUB_TOKEN=... git push origin main

# Tag-based
git commit -m "Fix auth service [DEPLOY:auth,api]"
git push origin main
```

### 5. GitHub Webhook Handler
**Location:** `scripts/triggers/github-webhook-handler.sh` (8.6K)

Integrates with GitHub webhook receiver:
- Validates webhook signature
- Extracts commit information
- Triggers deployment
- Posts status back to GitHub
- Handles webhook errors

### 6. Admin Script
**Location:** `scripts/triggers/install.sh` (11K)

Setup and configuration:
```bash
# Full setup
bash scripts/triggers/install.sh

# Local hooks only (developers)
bash scripts/triggers/install.sh --local-only

# Remote post-receive setup
bash scripts/triggers/install.sh --remote-setup

# Verify installation
bash scripts/triggers/install.sh verify
```

---

## Installation & Configuration

### For Developers (Local Machine)

```bash
# 1. Install Git hooks
bash scripts/triggers/install.sh --local-only

# 2. Configure environment (optional)
cat > .deployment.env <<EOF
export TARGET_HOST=192.168.168.42
export SERVICE_ACCOUNT=automation
export SSH_KEY=~/.ssh/automation_ed25519
export SLACK_WEBHOOK="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
EOF

# 3. Ensure SSH key exists
ssh-keygen -t ed25519 -f ~/.ssh/automation_ed25519

# 4. Test connectivity
ssh -i ~/.ssh/automation_ed25519 automation@192.168.168.42 "echo 'Connected!'"

# 5. Verify installation
bash scripts/triggers/install.sh verify

# 6. Try first deployment
git push origin main  # Automatic fresh build triggered!
```

### For Operators (Server Setup)

```bash
# 1. Copy deployment trigger script to server
scp -r scripts/triggers/ automation@192.168.168.42:/opt/self-hosted-runner/

# 2. Install post-receive hook
bash scripts/triggers/install.sh --remote-setup

# 3. Configure Slack webhook (optional)
export SLACK_WEBHOOK="https://hooks.slack.com/services/..."
gcloud secrets create slack-webhook --data-file=-

# 4. Test webhook delivery
bash scripts/triggers/test-integration.sh --slack

# 5. Verify system
ssh automation@192.168.168.42 "bash /opt/self-hosted-runner/scripts/triggers/install.sh verify"
```

### GitHub Webhook Setup (Optional)

```
Repository → Settings → Webhooks → Add webhook

Configuration:
  URL: https://your-webhook-receiver.com/
  Events: Pushes, Pull Requests
  Secret: (generate secure secret)

Payload example will post to your webhook receiver which then:
  1. Validates signature
  2. Extracts commit info
  3. Calls deployment trigger
  4. Posts status to GitHub
```

---

## Deployment Workflow

### Step 1: Developer Pushes Code
```bash
$ git commit -m "Fix authentication bug"
$ git push origin main
✅ Push successful
```

### Step 2: Pre-Push Hook
- Runs automated tests
- Checks for secrets
- Verifies code quality
- Validates deployment readiness

### Step 3: Push Received (Server)
- Post-receive hook triggered
- Detects main branch push
- Launches deployment asynchronously
- Confirms to git client

### Step 4: Deployment Trigger Starts
```
[INFO] Post-push deployment trigger initiated
[INFO] Target: 192.168.168.42
[STEP] Creating version backup...
[SUCCESS] Backup created: backup-abc123-20260314_123456
[STEP] Syncing code to target...
[SUCCESS] Code synced
```

### Step 5: Fresh Build Executes
On target host runs:
```bash
TARGET_HOST=192.168.168.42 bash deploy-worker-node.sh
```

This performs:
1. **Phase 1:** Mandate validation (blocks cloud ops)
2. **Phase 2:** Clean slate (removes all previous state)
3. **Phase 3:** Fresh provisioning (complete rebuild)
4. **Phase 4:** Fresh credentials (Ed25519 SSH keys)

### Step 6: Verification
```
[STEP] Verifying deployment...
✅ No cloud credentials present
✅ Target is on-prem (192.168.168.42)
✅ Fresh timestamps on all components
✅ All services operational
✅ Fresh SSH keys deployed
```

### Step 7: Notifications
**Slack:**
```
✅ Deployment Successful (Fresh Build)
Target: 192.168.168.42
Type: Complete Rebuild
Commit: abc123def456789...
Duration: 4m 23s
```

**GitHub:**
- Commit status updated to ✅ **success**
- Comment: "Fresh build deployment successful"

---

## Auto-Rollback on Failure

If deployment fails at any stage:

1. **Deployment Fails**
   ```
   ❌ Fresh build deployment FAILED
   [STEP] Initiating auto-rollback...
   ```

2. **Version Backup Used**
   ```
   [STEP] Rolling back to version: abc123def456
   [SUCCESS] Rollback completed to: abc123def456
   ```

3. **Previous Version Restored**
   - Code reverted to last working commit
   - Services restarted with previous config
   - Data integrity maintained

4. **Notifications**
   ```
   ⚠️ Auto-Rollback Triggered
   Deployment failed and was auto-rolled back
   Commit: abc123def456789...
   
   Manual investigation required!
   ```

**To Skip Auto-Rollback (not recommended):**
```bash
SKIP_ROLLBACK=true git push origin main
```

---

## Configuration Options

### Environment Variables

```bash
# Target Configuration
TARGET_HOST=192.168.168.42            # Deployment target
SERVICE_ACCOUNT=automation            # SSH account
SSH_KEY=~/.ssh/automation_ed25519    # SSH key path

# Notifications
SLACK_WEBHOOK=https://hooks.slack.com/...    # Slack webhook
GITHUB_TOKEN=ghp_...                          # GitHub API token

# Behavior Options
DRY_RUN=false                    # Preview without deploying
SKIP_ROLLBACK=false              # Disable auto-rollback
DEBUG=false                       # Verbose logging

# Detection Strategy
DETECTION_STRATEGY=full           # full|smart|tags
```

### .deployment.env File
```bash
# Create in repository root
cat > .deployment.env <<'EOF'
export TARGET_HOST=192.168.168.42
export SERVICE_ACCOUNT=automation
export SSH_KEY=~/.ssh/automation_ed25519
export SLACK_WEBHOOK="https://hooks.slack.com/services/..."
export DETECTION_STRATEGY=full
EOF

# Source before operations
source .deployment.env
git push origin main
```

---

## Logs & Monitoring

### Deployment Logs
```
Location: logs/deployments/YYYYMMDD_HHMMSS.log

Contains:
  - Pre-deployment validation
  - SSH connectivity checks
  - Version backup creation
  - Code sync progress
  - Fresh build step-by-step output
  - Post-deployment verification
  - Rollback log (if triggered)
```

### Last Deployment Status
```json
File: .last-deployment
{
  "deployment_sha": "abc123...",
  "deployment_time": "2026-03-14T12:34:56Z",
  "target_host": "192.168.168.42",
  "status": "success",
  "duration_seconds": 263,
  "backup_path": ".deployment-backups/backup-abc123-...",
  "mandate": "Fresh Build (Complete Rebuild) - On-Prem Only"
}
```

### Version Backups
```
Location: .deployment-backups/

Structure:
  backup-abc123-20260314_123456       (git state marker)
  backup-abc123-20260314_123456.sha   (previous commit SHA)
  backup-abc123-20260314_123456.metadata (backup info)
  backup-abc123-20260314_123456.version (version tag)
```

---

## Troubleshooting

### Issue: "Deployment trigger script not found"

**Solution:**
```bash
# Ensure scripts are in place
ls -la scripts/triggers/post-push-deploy.sh
ls -la .githooks/post-push

# Reinstall
bash scripts/triggers/install.sh
```

### Issue: "SSH connection failed"

**Solution:**
```bash
# Verify SSH key exists
ls -la ~/.ssh/automation_ed25519

# Test connectivity
ssh -i ~/.ssh/automation_ed25519 automation@192.168.168.42 "echo OK"

# Configure SSH key in .deployment.env
export SSH_KEY=~/.ssh/automation_ed25519
source .deployment.env
```

### Issue: "Auto-rollback failed - MANUAL INTERVENTION REQUIRED"

**Solution:**
```bash
# SSH to target host
ssh automation@192.168.168.42

# Check current status
systemctl status monitoring-* alert-triage.timer

# Manually rollback if needed
cd /opt/self-hosted-runner
git log --oneline -5  # See recent commits
git checkout <previous-sha>
bash deploy-worker-node.sh

# Verify fresh build
bash scripts/enforce/verify-fresh-build-deployment.sh
```

### Issue: "Deployment blocked by fresh build mandate"

**Solution:**
This is intentional! The mandate prevents cloud deployments. Check:

```bash
# 1. Verify target is on-prem
echo $TARGET_HOST  # Should be 192.168.168.42

# 2. Check no cloud credentials
env | grep -i 'GOOGLE\|AWS\|AZURE'

# 3. If forcing on-prem:
unset GOOGLE_APPLICATION_CREDENTIALS AWS_* AZURE_*
git push origin main
```

---

## Daily Operations

### Monitoring Deployment Status
```bash
# Watch live deployment
tail -f logs/deployments/$(date +%Y%m%d)_*.log

# Check last deployment
cat .last-deployment | jq .

# List all backups
ls -la .deployment-backups/
```

### Manual Deployment Override
```bash
# Skip automatic deployment
SKIP_DEPLOYMENT=true git push origin main

# Deploy manually later
bash scripts/triggers/post-push-deploy.sh

# Dry-run first
DRY_RUN=true bash scripts/triggers/post-push-deploy.sh
```

### Version Rollback
```bash
# Find backup to restore
ls -la .deployment-backups/

# Check backup metadata
cat .deployment-backups/backup-ABC123-20260314_*.metadata | jq .

# Rollback to specific version
bash scripts/triggers/post-push-deploy.sh --rollback backup-ABC123-20260314_123456
```

---

## Integration with Fresh Build Mandate

This automated deployment system is fully integrated with the **Fresh Build Mandate** enforcement:

1. **On-Prem Only (192.168.168.42)**
   - Deployments strictly limited to on-prem targets
   - Cloud credentials automatically rejected

2. **Complete Fresh Builds**
   - Every deployment is a complete rebuild
   - No incremental updates allowed
   - Clean slate enforcement before each deployment

3. **Fresh Credentials**
   - Ed25519 SSH keys generated per deployment
   - Service accounts configured fresh each time
   - Zero credential reuse

4. **Multi-Layer Enforcement**
   - Cloud prevention in deployment scripts
   - Mandate validation before trigger execution
   - Verification checks post-deployment

5. **Audit Trail**
   - Complete git history of all deployments
   - Version backups for every deployment
   - Comprehensive logging for compliance

---

## Security Considerations

### SSH Keys
- Use Ed25519 keys (modern cryptography)
- Store in secure location (`.ssh/` with 600 permissions)
- Rotate annually
- Use separate deploy key for automation

### Webhook Secrets
- Use HMAC-SHA256 signatures
- Rotate webhook secrets quarterly
- Log all webhook deliveries
- Monitor for failed signature validations

### Slack Integration
- Use secure webhook URLs (one per channel)
- Rotate webhooks annually
- Avoid sending sensitive data in notifications
- Monitor webhook delivery failures

### Git Configuration
- Protect main branch (require PR reviews)
- Enforce signed commits (GPG)
- Use strong GitHub personal access tokens
- Enable branch protection rules

---

## References

- [Fresh Build Mandate](../../ENFORCEMENT_RULES.md#rule-6-fresh-build-deployment)
- [Deployment Instructions](../../DEPLOYMENT_INSTRUCTIONS.md)
- [Code Mandates](../../CODE_MANDATES.md)
- [Post-push Deploy Script](./post-push-deploy.sh)
- [Installation Script](./install.sh)

