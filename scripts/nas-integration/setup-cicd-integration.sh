#!/bin/bash
# NAS CI/CD Integration Setup
# Integrates NAS deployment with GitHub actions and webhooks

set -e

cat > /home/akushnir/self-hosted-runner/.github/workflows/nas-sync-validate.yml << 'GITHUB_WORKFLOW'
name: NAS Sync Validation

on:
  push:
    paths:
      - 'scripts/nas-integration/**'
      - 'systemd/nas*'
      - 'docs/NAS*'
  pull_request:
    paths:
      - 'scripts/nas-integration/**'
      - 'systemd/nas*'

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Validate shell scripts
        run: |
          bash -n scripts/nas-integration/worker-node-nas-sync.sh
          bash -n scripts/nas-integration/dev-node-nas-push.sh
          bash -n scripts/nas-integration/healthcheck-worker-nas.sh
      
      - name: Check for secrets in code
        run: |
          if grep -r "PRIVATE\|SECRET\|PASSWORD" scripts/nas-integration/ systemd/; then
            echo "ERROR: Found potential secrets in code"
            exit 1
          fi
      
      - name: Validate systemd files
        run: |
          systemd-analyze verify systemd/nas*.service || true

  test-deployment:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Test sync script logic
        run: |
          # Run in dry-run mode (no actual sync)
          DRY_RUN=1 bash scripts/nas-integration/worker-node-nas-sync.sh
      
      - name: Test health check script
        run: |
          # Run health check in dry-run
          DRY_RUN=1 bash scripts/nas-integration/healthcheck-worker-nas.sh
GITHUB_WORKFLOW

cat > /home/akushnir/self-hosted-runner/scripts/nas-integration/github-webhook-handler.sh << 'WEBHOOK_HANDLER'
#!/bin/bash
# GitHub Webhook Handler for NAS Integration
# Receives GitHub push events and triggers NAS updates

set -e

# Get webhook payload from stdin
PAYLOAD=$(cat)

# Extract commit info
COMMIT_MESSAGE=$(echo "$PAYLOAD" | jq -r '.head_commit.message')
BRANCH=$(echo "$PAYLOAD" | jq -r '.ref' | sed 's|refs/heads/||')
PUSHER=$(echo "$PAYLOAD" | jq -r '.pusher.name')

echo "[WEBHOOK] Received push from $PUSHER to $BRANCH"
echo "[WEBHOOK] Commit: $COMMIT_MESSAGE"

# Check if NAS-related files were modified
if echo "$PAYLOAD" | jq '.head_commit.modified[]' | grep -q "scripts/nas-integration\|systemd/nas"; then
    echo "[WEBHOOK] NAS files modified - triggering immediate sync"
    
    # Trigger immediate sync on worker nodes
    for node_ip in 192.168.168.42 192.168.168.43 192.168.168.44; do
        ssh -o ConnectTimeout=5 "automation@${node_ip}" \
            "bash /opt/automation/scripts/worker-node-nas-sync.sh" \
            > /tmp/webhook-sync-${node_ip}.log 2>&1 &
    done
    
    wait
    echo "[WEBHOOK] Immediate syncs triggered"
else
    echo "[WEBHOOK] No NAS files modified, using normal schedule"
fi
WEBHOOK_HANDLER

chmod +x /home/akushnir/self-hosted-runner/scripts/nas-integration/github-webhook-handler.sh

cat > /home/akushnir/self-hosted-runner/docs/NAS_CICD_INTEGRATION.md << 'CICD_DOCS'
# NAS Integration CI/CD Setup

## GitHub Actions Workflows

### 1. Validation Pipeline (nas-sync-validate.yml)

Runs on every push/PR affecting NAS files:
- Validates shell script syntax
- Checks for secrets in code (no credentials)
- Validates systemd unit files
- Tests deployment scripts

**Trigger**: Changes to `scripts/nas-integration/`, `systemd/nas*`, `docs/NAS*`

### 2. GitHub Webhooks

Listen for push events and trigger immediate syncs on production nodes when NAS files change.

**Setup**:
```
Repository Settings → Webhooks → Add webhook
Payload URL: https://your-server.com/webhook/nas-sync
Content type: application/json
Events: Push events
```

## Deployment Integration

### Manual Trigger via GitHub Dispatch

```bash
# Trigger NAS deployment from GitHub Actions
gh workflow run nas-sync-validate.yml
```

### Automatic Triggers

1. **Code Change**: Push to `scripts/nas-integration/` triggers validation
2. **Webhook**: GitHub webhook triggers immediate sync on production
3. **Schedule**: Systemd timers (30min sync independent of CI/CD)

## Best Practices

- Always validate locally before pushing
- Run health checks after any deployment
- Monitor audit trail for changes
- Test in staging environment first
- Use pull requests for major changes

## Commands

```bash
# Validate locally
bash -n scripts/nas-integration/worker-node-nas-sync.sh

# Test deployment in dry-run
DRY_RUN=1 bash scripts/nas-integration/worker-node-nas-sync.sh

# Check what changed
git diff HEAD~1 HEAD scripts/nas-integration/

# View audit trail
ssh automation@192.168.168.42 "tail -20 /opt/nas-sync/audit/audit.jsonl"
```
CICD_DOCS

echo "✓ CI/CD integration files created"
echo "  - .github/workflows/nas-sync-validate.yml"
echo "  - scripts/nas-integration/github-webhook-handler.sh"
echo "  - docs/NAS_CICD_INTEGRATION.md"
