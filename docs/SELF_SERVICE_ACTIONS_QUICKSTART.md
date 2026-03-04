# Self-Service Actions - Integration & Quick Start

**Get your self-hosted runners executing agentic workflows in 15 minutes.**

---

## 🎯 What You'll Have After This

✅ Self-service agentic workflows running on your runners  
✅ Local LLM inference (Ollama) - zero external API calls  
✅ First workflow triggered and working  
✅ Roadmap for scaling to your team's needs

---

## Phase 1: Verify Prerequisites (5 min)

### 1. Check Your Runner Setup

```bash
# Verify self-hosted runners exist
gh run list --limit 1

# You should see at least one runner available
# Look in Settings → Actions → Runners
```

### 2. Verify Git & GitHub CLI

```bash
git --version  # v2.30+
gh --version   # v2.20+

# Authenticate if needed
gh auth login
```

### 3. Note Your Runner Label

```bash
# Find your runner's label(s)
gh api repos/{owner}/{repo}/actions/runners | jq '.runners[] | {name, labels}'

# Likely: "elevatediq-runner" or "ubuntu-latest"
# We'll use this in workflows
```

---

## Phase 2: Deploy Ollama to Runners (5 min)

### Option A: Already in Packer Build ✅

If you're using the updated Packer build (rebuilding AMIs):
```bash
# Just rebuild your runner images
cd packer
packer build -var="build_id=2026-03-04" runner-image.pkr.hcl
```

Ollama will be pre-installed in the new images.

### Option B: Manually on Existing Runners

SSH into each runner:
```bash
# Install Ollama
curl -fsSL https://ollama.ai/install.sh | sh

# Enable service
sudo systemctl enable ollama
sudo systemctl start ollama

# Pull a model (takes ~5 min first time)
ollama pull llama2

# Verify
curl http://localhost:11434/api/tags
```

---

## Phase 3: Deploy Agentic Workflows (5 min)

### Step 1: Clone & Update Repo

```bash
cd ~/self-hosted-runner

# Pull latest changes
git pull origin main

# Create feature branch (best practice)
git checkout -b feature/self-service-workflows
```

### Step 2: Compile Example Workflows

```bash
# List available workflows
./scripts/compile-agentic-workflows.sh list

# Compile all into .lock.yml files
./scripts/compile-agentic-workflows.sh compile-all

# You should see .lock.yml files created:
ls -la .github/workflows/agentic/*.lock.yml
```

### Step 3: Verify & Commit

```bash
# Check what you're committing
git status

# Add workflows
git add .github/workflows/agentic/

# Commit
git commit -m "chore: add self-service agentic workflows

- auto-fix: Automated code quality checks on PRs
- pr-review: Structured PR review checklist
- dependency-audit: Weekly security/dependency audit

Uses local Ollama for inference - zero external calls."

# Push
git push -u origin feature/self-service-workflows
```

---

## Phase 4: Test First Workflow (TBD Minimum)

### Test 1: Trigger Auto-Fix on a PR

```bash
# Create a feature branch with intentional issues
git checkout -b test/auto-fix-demo

# Add a file with known issues
cat > test-broken.js <<'EOF'
// Missing error handling
async function fetchUser(id) {
  const res = await fetch(`/api/users/${id}`);
  return res.json();  // ❌ No error handling
}

// Unused import
import * as unused from 'lodash';

module.exports = { fetchUser };
EOF

git add test-broken.js
git commit -m "test: add broken code for auto-fix demo"
git push origin test/auto-fix-demo
```

### Create PR & Wait

```bash
# Open PR on GitHub
# https://github.com/YOUR-ORG/self-hosted-runner/compare/main...test/auto-fix-demo

# Watch for auto-fix workflow to trigger
# GitHub Actions → Workflows → Auto-Fix Common Code Issues

# Expected result:
# ✅ Workflow queued on your self-hosted runner
# 🤖 Ollama analyzes code
# 💬 Auto-fix comments on PR with suggestions
```

**Success Indicators:**
- ✅ Workflow execution shows on Actions tab
- ✅ Comment appears on PR from your account
- ✅ Comment suggests real improvements

---

## Phase 5: Integrate with Your Stack

### Option A: Add to Portal Dashboard

Update [ElevatedIQ-Mono-Repo/apps/portal/src/api/workflows.ts](../../ElevatedIQ-Mono-Repo/apps/portal/src/api/workflows.ts):

```typescript
// Fetch workflow status from GitHub Actions
export async function getAgenticWorkflows() {
  const res = await fetch(`/api/repos/actions/workflows`);
  return res.json();
}

// Mock data for dev
export const mockAgenticWorkflows = [
  {
    id: 1,
    name: 'Auto-Fix',
    status: 'active',
    lastRun: '2 hours ago',
    successRate: 95
  },
  {
    id: 2,
    name: 'PR Review',
    status: 'active',
    lastRun: '30 mins ago',
    successRate: 98
  }
];
```

### Option B: Add to Services Monitoring

Update [services/provisioner-worker/index.js](../../services/provisioner-worker/index.js):

```javascript
// Check Ollama health
async function checkOllamaHealth() {
  try {
    const res = await fetch('http://localhost:11434/api/tags');
    const data = await res.json();
    return {
      status: 'healthy',
      models: data.models?.length || 0
    };
  } catch (err) {
    return { status: 'unhealthy', error: err.message };
  }
}

// Export health status
app.get('/health/ollama', async (req, res) => {
  const health = await checkOllamaHealth();
  res.json(health);
});
```

### Option C: Add Slack Notifications

In your workflow markdown, add notification step:

```markdown
## Send Slack Notification

When workflow completes, notify #ci-cd with:
- Workflow name
- Success/failure status
- Link to run

Use Slack webhook: ${{ secrets.SLACK_WEBHOOK_URL }}
```

---

## 📋 Checklist: Self-Service Enabled

- [ ] **Infra:** Ollama installed on runners
- [ ] **Workflows:** Markdown files in `.github/workflows/agentic/`
- [ ] **Compiled:** `.lock.yml` files generated
- [ ] **Committed:** Both `.md` and `.lock.yml` pushed to repo
- [ ] **Tested:** Created and triggered a test PR
- [ ] **Monitored:** Viewed execution logs in GitHub Actions
- [ ] **Documented:** Team knows how to create new workflows
- [ ] **Backlogged:** Logged improvement ideas

---

## 🚀 Next: Scaling Up

### Create Your Own Workflow

1. Copy a template from [docs/AGENTIC_WORKFLOWS_EXAMPLES.md](./AGENTIC_WORKFLOWS_EXAMPLES.md)
2. Customize for your use case
3. Save to `.github/workflows/agentic/my-workflow.md`
4. Compile: `./scripts/compile-agentic-workflows.sh compile .github/workflows/agentic/my-workflow.md`
5. Test in a feature branch
6. Merge when ready

### Add More Workflows

Popular additions:
- Issues triage (auto-label, ask for info)
- Stale bot (flag old PRs)
- Documentation generation (auto-create API docs)
- Performance monitoring (alert on regressions)
- Security audit (scan for vulnerabilities)

See [docs/AGENTIC_WORKFLOWS_EXAMPLES.md](./AGENTIC_WORKFLOWS_EXAMPLES.md) for templates.

### Extend with Custom Models

```bash
# SSh to runner
ollama pull mistral      # Faster model
ollama pull neural-chat  # Better for code

# Update workflows to use specific model names
# In .lock.yml agent step:
# OLLAMA_MODEL=mistral ./run-agent.sh
```

---

## 🔍 Troubleshooting

### Workflow Didn't Trigger

```bash
# Check if workflow is enabled
cat .github/workflows/agentic/auto-fix.lock.yml | head -5

# Check GitHub Actions settings
# Settings → Actions → Disable workflows? (Should be NO)

# Verify runner is online
ssh runner-instance
systemctl status github-actions-runner

# Check runner logs
systemctl status github-actions-runner -l
```

### Ollama Not Found

```bash
# Verify on runner
ssh runner-instance
curl http://localhost:11434/api/tags

# If not running:
sudo systemctl restart ollama

# Check logs:
sudo journalctl -u ollama -n 20 -f
```

### Workflow Compiled But Not Running

```bash
# Verify syntax
./scripts/compile-agentic-workflows.sh validate \
  .github/workflows/agentic/auto-fix.md

# Check that .lock.yml was created
ls -la .github/workflows/agentic/auto-fix.lock.yml

# Push to repo
git add .github/workflows/agentic/auto-fix.lock.yml
git push origin main

# GitHub should pick it up within 30 seconds
```

### Agent Output Not Appearing

```bash
# Check workflow run logs
gh run list --workflow=auto-fix.lock.yml
gh run view <RUN_ID> --log

# Check if PR is on an open PR (not draft)
# Check if workflow has permission to comment
# (permissions.pull-requests: write needed)
```

---

## 📖 Full Documentation

- **Setup Details:** [docs/AGENTIC_WORKFLOWS_SETUP.md](./AGENTIC_WORKFLOWS_SETUP.md)
- **Advanced Examples:** [docs/AGENTIC_WORKFLOWS_EXAMPLES.md](./AGENTIC_WORKFLOWS_EXAMPLES.md)
- **Compilation Details:** [scripts/compile-agentic-workflows.sh](../scripts/compile-agentic-workflows.sh)

---

## 🎓 Team Onboarding

Share this with your team:

1. **Developers:** Link to [AGENTIC_WORKFLOWS_EXAMPLES.md](./AGENTIC_WORKFLOWS_EXAMPLES.md)
2. **DevOps:** Share compilation process in [AGENTIC_WORKFLOWS_SETUP.md](./AGENTIC_WORKFLOWS_SETUP.md)
3. **Everyone:** Show working example PR with auto-fix comments

---

## ✅ Success Metrics

Track these to measure self-service impact:

| Metric | Baseline | Goal (30 days) | Goal (90 days) |
|--------|----------|---|---|
| Workflows running | 0 | 5+ | 10+ |
| PRs with auto-review | 0% | 30%+ | 70%+ |
| Bugs caught pre-review | 0 | 5/week | 15/week |
| Team time saved (hrs/week) | 0 | 5+ | 15+ |
| Runner utilization | TBD | +20% | +40% |

---

## 🎉 You're Done!

Your repo now has **self-service actions** running on your infrastructure.

- ✅ No GitHub Secrets needed for model inference
- ✅ No external API calls at runtime
- ✅ No additional costs for execution
- ✅ Fully audit-able and traceable
- ✅ Can evolve without CI/CD freezes

**Next step:** Merge your feature branch to main and celebrate! 🚀

Questions? Check the docs or review example workflows in action.
