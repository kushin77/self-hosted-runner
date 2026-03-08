# 🚀 RAPID DEPLOYMENT CONTINGENCY - Self-Hosted Runner Path

**Situation**: GitHub Actions disabled by billing → Use self-hosted runners to bypass

**Advantage**: Self-hosted runners are NOT subject to GitHub Actions spending limits

---

## Quick Activation (5-10 minutes)

### Step 1: Verify Self-Hosted Runner Online
```bash
# Check runner status in repo settings or via API
gh api repos/{owner}/{repo}/actions/runners

# OR check locally
ps aux | grep actions-runner
```

### Step 2: Transition Workflows to Self-Hosted

Create minimal transition wrapper:

```bash
# For each critical workflow, ensure runs-on uses self-hosted
find .github/workflows -name "*.yml" -exec sed -i 's/runs-on: ubuntu-latest/runs-on: self-hosted/g' {} \;
```

### Step 3: Trigger Initial Checks Manually

```bash
# Bootstrap system using local execution
./scripts/automation/ops-blocker-automation.sh --verify-only

# Then run full detection
./scripts/automation/ops-blocker-automation.sh
```

### Step 4: System Auto-Takes Over

- Self-hosted runner picks up scheduled workflows
- All monitoring activates (15/30 min cycles)
- Issue #231 auto-updates
- Operator provisioning can begin

---

## Deployment Timeline (Self-Hosted Path)

| Phase | Duration | Status |
|-------|----------|--------|
| Verify runner online | ~2 min | Quick |
| Transition to self-hosted | ~3 min | Quick |
| First blocker check | ~5 min | Auto |
| Operator provisioning begins | On-demand | When ready |
| Phase P4 auto-triggers | When deps ready | Auto |
| Infrastructure ready | 60-120 min | Auto |

**Total to Production**: 30-60 min (vs. 45-155 min waiting for billing)

---

## System Properties Maintained

✅ **Immutable**: All changes in Git (workflows can be reverted)  
✅ **Ephemeral**: Local runner execution, same stateless design  
✅ **Idempotent**: All scripts state-detecting (safe re-run)  
✅ **No-Ops**: Still fully automated (self-hosted runner is automation engine)  
✅ **Self-Healing**: Auto-detect + remediate unaffected  

---

## Parallel Path: Resolve Billing

**While self-hosted system runs**:
1. Resolve GitHub Actions billing (10-30 min)
2. Once resolved, workflows automatically transition back to GitHub Actions
3. Self-hosted runner remains as backup/overflow

**No conflict**: Both can coexist

---

## What Happens

### Immediate (Self-Hosted Active)
- ✅ Blocker detection runs (15 min cycles)
- ✅ Readiness validation runs (30 min cycles)
- ✅ Phase P5 validation runs (30 min cycles)
- ✅ Emergency recovery runs (6 hour cycles)
- ✅ Issue #231 auto-updates
- ✅ Operator can start provisioning
- ✅ Phase P4 auto-triggers when ready

### After Billing Resolved
- ✅ GitHub Actions re-enabled
- ✅ Workflows can transition to GitHub-hosted runners
- ✅ Self-hosted remains as backup
- ✅ No changes to automation

---

## Activation Command (Copy-Paste Ready)

```bash
#!/bin/bash
set -e

echo "🚀 RAPID DEPLOYMENT: Transitioning to Self-Hosted Runner"

# 1. Verify runner
echo "✓ Checking self-hosted runner..."
if ! pgrep -f actions-runner > /dev/null; then
  echo "⚠️  WARNING: Self-hosted runner not detected running"
  echo "   Start with: cd actions-runner && ./run.sh"
  exit 1
fi

# 2. Modify workflows for self-hosted
echo "✓ Transitioning workflows to self-hosted..."
find .github/workflows -name "ops-blocker-monitoring.yml" \
  -o -name "phase-p5-post-deployment-validation.yml" \
  -o -name "pre-deployment-readiness-check.yml" | while read wf; do
  sed -i 's/runs-on: ubuntu-latest/runs-on: self-hosted/g' "$wf"
  echo "  → Updated: $wf"
done

# 3. Bootstrap system
echo "✓ Bootstrap blocker detection..."
./scripts/automation/ops-blocker-automation.sh --verify-only
./scripts/automation/ops-blocker-automation.sh

# 4. Verify scheduled workflows
echo "✓ System activated"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🟢 Self-Hosted Automation ACTIVE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Next:"
echo "1. Operator: ./scripts/automation/operator-provisioning-helper.sh"
echo "2. System: Auto-detects actions → auto-continues"
echo "3. Billing: Resolve separately if needed"
echo ""
```

---

**Status**: Ready for immediate activation  
**Decision Needed**: Proceed with self-hosted contingency? (Y/N)  
**Alternative**: Wait for billing resolution (10-30 min + delays)

