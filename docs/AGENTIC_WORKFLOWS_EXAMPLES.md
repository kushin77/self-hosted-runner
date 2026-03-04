# Agentic Workflows - Complete Examples & Recipes

Production-ready Markdown workflow templates you can use immediately.

---

## 📚 Quick Reference

| Use Case | File | Trigger | Difficulty |
|----------|------|---------|------------|
| Code Quality | [auto-fix.md](#auto-fix) | PR opened/sync | ⭐ Easy |
| PR Triage | [pr-review.md](#pr-review) | PR opened | ⭐ Easy |
| Dependency Mgmt | [dependency-audit.md](#dependency-audit) | Weekly | ⭐⭐ Medium |
| Issue Triage | [issue-classifier.md](#issue-classifier) | Issue opened | ⭐⭐ Medium |
| Docs Generation | [docs-generator.md](#docs-generator) | On demand/schedule | ⭐⭐⭐ Hard |
| Performance Monitor | [perf-monitor.md](#performance-monitor) | Schedule/workflow_run | ⭐⭐⭐ Hard |

---

## Example 1: Auto-Fix (Easy) {#auto-fix}

**Location:** `.github/workflows/agentic/auto-fix.md`

**What it does:**
- Runs on PR opened/sync
- Analyzes code for common issues
- Leaves constructive review comments
- Uses Ollama for local analysis → zero external calls

**When to use:**
- First workflow to test
- Good for onboarding teams to the system
- Low-stakes: reading only, commenting only

**Setup:**
```bash
# Copy to your repo
cp docs/examples/auto-fix.md .github/workflows/agentic/

# Compile (creates .lock.yml)
./scripts/compile-agentic-workflows.sh compile .github/workflows/agentic/auto-fix.md

# Git it and push
git add .github/workflows/agentic/
git commit -m "chore: add auto-fix agentic workflow"
git push origin feature/self-service-workflows
```

**Trigger test:**
```bash
# Create a test PR with intentional issue
git checkout -b test/auto-fix-demo
cat > broken.js <<'EOF'
// Missing error handling
async function fetchData(url) {
  const response = await fetch(url);  // ❌ No error handling
  return response.json();
}

// Unused import
import * as unused from 'lodash';

module.exports = { fetchData };
EOF

git add broken.js
git commit -m "test: intentionally broken for auto-fix demo"
git push origin test/auto-fix-demo

# Open PR on GitHub
# Watch auto-fix.lock.yml trigger and comment
```

---

## Example 2: PR Review Checklist (Easy) {#pr-review}

**Location:** `.github/workflows/agentic/pr-review.md`

**What it does:**
- Generates structured review checklist
- Flags missing documentation
- Identifies potential issues before human review
- Formats findings for easy triage

**Use cases:**
- Large or distributed teams
- Projects with many reviewers
- Reducing review time for standard checks

**Configuration:**
```yaml
---
name: PR Review Checklist
on:
  pull_request:
    types: [opened, synchronize]
    paths-ignore:
      - 'docs/**'
      - '*.md'
permissions:
  pull-requests: write
runs-on: elevatediq-runner
---
```

---

## Example 3: Dependency Audit (Medium) {#dependency-audit}

**Location:** `.github/workflows/agentic/dependency-audit.md`

**What it does:**
- Weekly scan of dependencies
- Identifies security vulnerabilities
- Creates GitHub issues (not PRs) for visibility
- Categorizes by severity

**Example output:**
```
## 🔴 Critical: Security Vulnerability

**Package:** lodash (v4.17.15)
**CVE:** CVE-2021-23337
**Fix Available:** Yes (v4.17.21)
**Impact:** High

Prototype pollution in lodash could allow arbitrary property injection.

**Action:** Upgrade to v4.17.21 immediately
```

**Setup:**
```bash
cp docs/examples/dependency-audit.md .github/workflows/agentic/

# Optional: schedule on different day
# Edit the cron to 'cron: "0 2 * * WED"' for Wednesdays

./scripts/compile-agentic-workflows.sh compile .github/workflows/agentic/dependency-audit.md
git add .github/workflows/agentic/dependency-audit*
git commit -m "chore: add weekly dependency audit"
git push
```

---

## Example 4: Issue Classifier (Medium) {#issue-classifier}

**Location:** `.github/workflows/agentic/issue-classifier.md`

```markdown
---
name: Automatic Issue Classification
description: Classify and triage incoming issues
on:
  issues:
    types: [opened]
permissions:
  issues: write
  contents: read
runs-on: elevatediq-runner
---

## Task: Classify and Label Issues

When a new issue is created, analyze the title and description to determine:

1. **Type:** bug | feature | documentation | question | chore
2. **Priority:** critical | high | medium | low
3. **Area:** portal | services | infrastructure | docs
4. **Component:** (specific subsystem)

## Output

Apply labels automatically:
- Type label (always)
- Priority label (always)
- Area label (always)
- Component label (if applicable)

Comment with summary:
\`\`\`
## 🏷️ Auto-Classification

- **Type:** [type]
- **Priority:** [priority]  
- **Area:** [area]
- **Component:** [component]

This issue has been classified. A maintainer will review shortly.
\`\`\`

## Rules

- If unsure about category, ask in comment rather than guessing
- Bug reports get "needs-triage" if unclear
- Duplicate reports get linked to original
- Spam/off-topic get hidden with explanation
```

---

## Example 5: Docs Generator (Hard) {#docs-generator}

**Location:** `.github/workflows/agentic/docs-generator.md`

```markdown
---
name: Auto-Generate API Docs
description: Generate and update API documentation
on:
  push:
    branches: [main]
    paths:
      - 'services/**/*.js'
      - 'services/**/*.ts'
  workflow_dispatch:
permissions:
  contents: write
  pull-requests: write
runs-on: elevatediq-runner
---

## Task: Generate API Documentation

Scan the codebase for exported functions and classes (TypeScript/JavaScript).

For each item, generate markdown documentation:

\`\`\`markdown
### \`functionName(param1, param2)\`

**Description:** One sentence summary

**Parameters:**
- \`param1\` (type): Description
- \`param2\` (type): Description

**Returns:** (type) Description

**Throws:** (error-type) When...

**Examples:**
\`\`\`js
// usage example
\`\`\`

**See also:** Links to related functions
\`\`\`

## Output

1. Generate or update \`docs/API.md\`
2. For significant changes, create a PR with:
   - Clear description of changes
   - Before/after comparison
   - Ready for human review

## Rules

- Skip private/internal functions (those with _ prefix)
- Extract JSDoc comments if present
- Generate from TypeScript types when available
- Group by module/service
```

---

## Example 6: Performance Monitor (Hard) {#performance-monitor}

**Location:** `.github/workflows/agentic/perf-monitor.md`

```markdown
---
name: Performance Regression Detection
description: Monitor and alert on performance regressions
on:
  push:
    branches: [main]
  pull_request:
    types: [opened, synchronize]
  schedule:
    - cron: '0 */4 * * *'
permissions:
  contents: read
  issues: write
  pull-requests: write
runs-on: high-mem-runner  # Use larger runner for tests
---

## Task: Monitor Application Performance

1. **Run Benchmarks:**
   - API response times
   - Build bundle size
   - Database query performance
   - Frontend render times

2. **Compare Metrics:**
   - Current vs main branch
   - Current vs historical trend
   - Flag regressions > 5%

3. **Report Findings:**
   - For PRs: comment with comparison
   - For main branch: create issue if regression > 10%
   - Include visualization/data table

## Example Output

\`\`\`
## 📊 Performance Analysis

### ✅ Good News
- Build time: 42.3s (↓ 2% improvement)
- Bundle size: 145KB (no change)

### ⚠️ Regressions Detected
- API /users endpoint: 245ms → 380ms (+55%) 🔴
- Database query N+1 in getProfile

### Recommendations
1. Review recent changes to user endpoint
2. Consider adding query cache or index
3. Run profiler to identify hotspot
\`\`\`

## Integration

- Link from Portal dashboard
- Export metrics to Prometheus (optional)
- Slack notification for critical regressions
```

---

## Example 7: Custom Workflow Template

Create your own by following this structure:

```markdown
---
name: Your Workflow Name
description: What this workflow does in one sentence
on:
  [trigger conditions]
permissions:
  [required permissions]
runs-on: elevatediq-runner
---

## Task: [Clear, actionable description]

What should the agent do? Be specific with:
- Input data available
- Processing steps
- Expected output format
- Success/failure criteria

## Context & Tools

You have access to:
- Full repository (read via git)
- GitHub API (via GITHUB_TOKEN)
- Ollama local model
- Recent PR/issue data

## Output Format

Describe expected output:
- Comment format
- Issue/PR creation
- File modifications
- Notifications

## Edge Cases

Document how to handle:
- Missing data
- Ambiguous cases
- Errors
```

---

## 🚀 Deployment Checklist

- [ ] Copy markdown files to `.github/workflows/agentic/`
- [ ] Run `./scripts/compile-agentic-workflows.sh compile-all`
- [ ] Verify `.lock.yml` files generated
- [ ] Commit both `.md` and `.lock.yml` files
- [ ] Ensure self-hosted runner is configured with label `elevatediq-runner`
- [ ] Verify Ollama is running: `systemctl status ollama`
- [ ] Test with simple workflow first (PR trigger)
- [ ] Monitor GitHub Actions logs for execution
- [ ] Refine based on feedback

---

## 🔧 Customization Guide

### Change Runner Label

All examples use `runs-on: elevatediq-runner`. To change:

```bash
sed -i 's/runs-on: elevatediq-runner/runs-on: my-runner-label/g' \
  .github/workflows/agentic/*.md
```

### Change Ollama Model

Default is `llama2`. To use faster model:

```bash
# In workflow, change:
# OLLAMA_MODEL: llama2
# to:
# OLLAMA_MODEL: neural-chat  # or mistral, etc.
```

### Disable Workflow Temporarily

Rename markdown file:
```bash
mv .github/workflows/agentic/auto-fix.md .github/workflows/agentic/auto-fix.md.disabled
./scripts/compile-agentic-workflows.sh compile-all
```

### Add New Trigger

Edit the frontmatter:
```yaml
on:
  pull_request:
    types: [opened, synchronize]
  issues:
    types: [opened, labeled]
  schedule:
    - cron: '0 0 * * MON'
  workflow_dispatch:  # Allow manual trigger
```

---

## 📦 Integration with Portal

The Portal app can display workflow results:

```typescript
// portal/src/api/workflows.ts
export async function getAgenticWorkflows() {
  const response = await fetch('/api/workflows/agentic');
  return response.json();
}

// portal/src/components/WorkflowDashboard.tsx
import { getAgenticWorkflows } from '@/api/workflows';

export function WorkflowDashboard() {
  const [workflows, setWorkflows] = useState([]);
  
  useEffect(() => {
    getAgenticWorkflows().then(setWorkflows);
  }, []);
  
  return (
    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
      {workflows.map(wf => (
        <WorkflowCard key={wf.id} workflow={wf} />
      ))}
    </div>
  );
}
```

---

## 🐛 Troubleshooting

**Workflow not triggering:**
```bash
# Check compilation
./scripts/compile-agentic-workflows.sh validate \
  .github/workflows/agentic/auto-fix.md

# Check GitHub Actions UI for errors
# Look at repository settings → Actions
```

**Ollama not responding:**
```bash
# SSH to runner
systemctl status ollama
systemctl restart ollama

# Test directly
curl http://localhost:11434/api/tags

# Check logs
journalctl -u ollama -n 50 -f
```

**Agent output not appearing:**
```bash
# Check workflow logs
gh run list --workflow=auto-fix.lock.yml
gh run view <run-id> --log

# Check permissions in .lock.yml
cat .github/workflows/agentic/auto-fix.lock.yml | grep -A10 "^permissions:"
```

---

## 📚 Next Steps

1. **Start with Example 1** (auto-fix) - lowest friction
2. **Test workflow triggering** - ensure integration works
3. **Refine based on feedback** - iterate with team
4. **Add Examples 2-3** - build portfolio of automation
5. **Create domain-specific workflows** - for your use cases
6. **Integrate with Portal** - add UI for visibility
7. **Monitor & improve** - track success and ROI

---

## 🎓 Learning Resources

- [GitHub Actions Docs](https://docs.github.com/en/actions)
- [Ollama Models](https://ollama.ai/library)
- [YAML Syntax](https://yaml.org/spec/)
- [Bash Best Practices](https://mywiki.wooledge.org/BashGuide)

---

See [AGENTIC_WORKFLOWS_SETUP.md](./AGENTIC_WORKFLOWS_SETUP.md) for architecture and deeper integration details.
