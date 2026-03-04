# Agentic Workflows - Self-Service CI/CD

Enable fully self-hosted, self-service AI-powered GitHub Actions workflows on your self-hosted runner infrastructure.

**Status:** ✅ Ready for Phase P2 Integration  
**Last Updated:** 2026-03-04

---

## 🎯 What Are Agentic Workflows?

Agentic Workflows combine:
- **Declarative Markdown** - Write workflows in plain English (`.md` files)
- **Automatic Compilation** - Converts Markdown → locked-down YAML (`.lock.yml`)
- **Self-Hosted Execution** - Runs entirely on your ElevatedIQ runners (no GitHub-hosted compute)
- **Local LLM Inference** - Uses Ollama + local models = zero external dependencies at runtime
- **Self-Service Evolution** - Workflows can propose improvements to themselves

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────┐
│          Your Git Repo (.github/workflows/)             │
├─────────────────────────────────────────────────────────┤
│  ├─ auto-test.md           (Human-readable Markdown)   │
│  ├─ auto-test.lock.yml     (Compiled, SHA-pinned)      │
│  ├─ fix-issues.md                                       │
│  └─ fix-issues.lock.yml                                │
└─────────────────────────────────────────────────────────┘
         ↓ (on trigger: PR, issue, schedule)
┌─────────────────────────────────────────────────────────┐
│     Your Self-Hosted Runner (ARC scale-set)            │
├─────────────────────────────────────────────────────────┤
│  ├─ Agent: Ollama (local, offline model)               │
│  ├─ Runtime: Parse .lock.yml + execute steps           │
│  ├─ Context: Full repo access + GitHub token           │
│  └─ Output: PRs, comments, labels, fixes               │
└─────────────────────────────────────────────────────────┘
```

---

## 🚀 Quick Start

### 1. Bootstrap (One-time setup)

```bash
# Clone repo
cd ~/self-hosted-runner

# Install gh extension (local dev machine or trusted CI)
gh extension install github/gh-aw

# Create your first Markdown workflow
mkdir -p .github/workflows/agentic
cat > .github/workflows/agentic/auto-fix.md <<'EOF'
---
name: Auto-Fix Common Issues
on:
  issues:
    types: [opened]
  schedule:
    - cron: '0 */6 * * *'
permissions:
  contents: write
  pull-requests: write
  issues: write
runs-on: elevatediq-runner
---

## Task: Analyze and fix common code issues

Review recent pull requests and issues. Identify patterns:
- Missing error handling
- Stale dependencies
- Documentation gaps

For each pattern found, create a focused fix PR with:
1. Root cause analysis
2. Implementation
3. Test coverage
4. Merge information

Use local Ollama model for code analysis—no external calls needed.
EOF

# Compile to locked workflow
gh aw compile .github/workflows/agentic/auto-fix.md

# Commit both files
git add .github/workflows/agentic/
git commit -m "chore: add self-service auto-fix workflow"
git push origin main
```

### 2. Runtime (Automatic on trigger)

When the trigger fires (e.g., new issue opened):
1. GitHub Actions dispatches the job to your runner pool
2. Runner picks up the `.lock.yml`
3. Executes compiled steps → invokes local agent
4. Agent runs Ollama for code analysis (all local)
5. Creates PRs/comments directly with GitHub token
6. No external API calls needed ✅

---

## 📋 Workflow Types & Examples

### Type 1: Reactive Automation (Triggered)

**Use case:** Respond to PRs, issues, code changes automatically

```markdown
---
name: PR Auto-Reviewer
on:
  pull_request:
    types: [opened, synchronize]
runs-on: elevatediq-runner
permissions:
  pull-requests: write
---

Review this PR for common issues:
- Security vulnerabilities
- Performance improvements
- Missing tests

Use the Ollama llama2 model to analyze code.
Leave structured review comments on the PR.
```

### Type 2: Scheduled Intelligence

**Use case:** Periodic codebase audits, dependency checks

```markdown
---
name: Weekly Dependency Audit
on:
  schedule:
    - cron: '0 0 * * MON'
runs-on: elevatediq-runner
permissions:
  contents: write
  pull-requests: write
---

Scan the repo for outdated dependencies and security issues.
For each critical finding, create a titled issue or PR.
Prioritize by severity and impact.
```

### Type 3: Self-Improving (Meta-Automation)

**Use case:** Workflow proposes improvements to itself

```markdown
---
name: Workflow Self-Improvement
on:
  workflow_run:
    workflows:
      - "PR Auto-Reviewer"
    types: [completed]
runs-on: elevatediq-runner
permissions:
  contents: write
  pull-requests: write
---

Analyze the execution of the "PR Auto-Reviewer" workflow.
If error rate > 5% or latency > 2min, create an issue or PR proposing:
- Performance improvements
- Bug fixes
- Definition of new workflow variants
```

---

## 🛠️ Workflow Compilation Process

### Manual Compilation (Recommended for DevOps)

```bash
# Compile a single workflow
gh aw compile .github/workflows/agentic/auto-fix.md

# Output: .github/workflows/agentic/auto-fix.lock.yml
# ├─ SHA-pinned GitHub Actions versions
# ├─ Hardened permissions
# ├─ Sandboxed agent invocation
# └─ Audit trail metadata
```

### Automated Compilation (CI-Driven)

```bash
# In your CI pipeline:
#!/bin/bash
set -euo pipefail

find .github/workflows/agentic -name "*.md" | while read md_file; do
  echo "Compiling $md_file..."
  gh aw compile "$md_file"
done

git add .github/workflows/agentic/*.lock.yml
git commit -m "chore: recompile agentic workflows" || true
git push origin main
```

---

## 🤖 Local Model Setup

### What Runs on Your Infrastructure?

Your Ollama service (installed in Packer) runs one of:
- `llama2` (7B) - Fast, good for lightweight analysis
- `neural-chat` (7B) - Better for code understanding
- `dolphin-mixtral` (8×7B) - Slower, most capable

### Download a Model

```bash
# SSH into a runner or during Packer build:
ollama pull llama2

# Or use environment variable in workflows:
OLLAMA_MODEL=llama2
```

### Use in Workflow

```bash
# In your agentic step:
ollama run llama2 "Analyze this code for bugs: $(cat file.js)"
```

---

## 🔒 Security Properties

| Property | Value | Note |
|----------|-------|------|
| **Model Data Flow** | Local → Runner → Local | No external LLM calls |
| **Repo Access** | Read (controlled scope) | GitHub token scoped per workflow |
| **Network** | Egress only to GitHub API | Ollama is local |
| **Permissions** | Minimal by default | Explicit per workflow |
| **Audit Trail** | GitHub Actions logs + Git history | Full traceability |

---

## 📝 Best Practices

### 1. Start Simple
Begin with reactive workflows triggered by PRs/issues. Easy to test and debug.

```markdown
on:
  pull_request:
    types: [opened]
```

### 2. Use Descriptive Markdown
Be explicit about what the agent should do. Include examples if possible.

```markdown
## Task: Suggest performance improvements

Analyze the PR diff. Look for:
- N+1 queries
- Unnecessary re-renders
- Memory leaks

For each issue, propose a specific code fix.
```

### 3. Require Human Review
Always have humans review before merge. Agents propose, humans approve.

```markdown
## Output Format

For each finding, create a comment formatted as:
- **Issue:** [description]
- **Severity:** [critical|high|medium]
- **Proposed Fix:** [code block]

Wait for human review before merging.
```

### 4. Monitor & Iterate
Track workflow success rates. Refine based on feedback.

```bash
# See execution logs
gh run list --workflow=auto-fix.lock.yml

# See latest run details
gh run view <run-id> --log
```

---

## 📦 Integration with Your ElevatedIQ Stack

### Portal Updates
The Portal app can display agentic workflow status:
```javascript
// portal/src/components/WorkflowDashboard.tsx
import { getAgenticWorkflows, mockAgenticWorkflows } from '@/api/workflows';

export default function WorkflowDashboard() {
  const [workflows] = useState(mockAgenticWorkflows);
  return (
    <div>
      <h1>Self-Service Workflows</h1>
      {workflows.map(wf => (
        <WorkflowCard key={wf.id} workflow={wf} />
      ))}
    </div>
  );
}
```

### Service Integration
Add Ollama health check to your provisioner-worker:
```javascript
// services/provisioner-worker/index.js
async function checkOllamaHealth() {
  const res = await fetch('http://localhost:11434/api/tags');
  if (res.ok) {
    logger.info('✅ Ollama is running and ready');
    return true;
  }
  throw new Error('Ollama unavailable');
}
```

---

## 🐛 Troubleshooting

### Workflow Not Triggering

1. **Check trigger conditions:**
   ```bash
   # View workflow file
   cat .github/workflows/agentic/auto-fix.lock.yml | grep -A5 "^on:"
   
   # Verify compilation
   gh aw compile --validate .github/workflows/agentic/auto-fix.md
   ```

2. **Check runner availability:**
   ```bash
   # SSH into a runner
   systemctl status github-actions-runner
   
   # Check Ollama is running
   systemctl status ollama
   ```

### Ollama Not Available

```bash
# Restart service
systemctl restart ollama

# Check logs
journalctl -u ollama -n 50 -f

# Manually test
curl http://localhost:11434/api/tags
```

### Compilation Fails

```bash
# Validate Markdown syntax
gh aw validate .github/workflows/agentic/auto-fix.md

# Check YAML frontmatter
head -20 .github/workflows/agentic/auto-fix.md
```

---

## 📚 Related Documentation

- [GitHub Agentic Workflows Docs](https://docs.github.com/en/actions/using-workflows/agentic-workflows)
- [Ollama Local Model Docs](https://ollama.ai)
- [Self-Hosted Runner Setup](./PHASE_P1_OPERATIONAL_RUNBOOKS.md)
- [Portal Development](../PORTAL_DEVELOPMENT.md)

---

## 🎯 Next Steps

1. **Review** this guide with your team
2. **Test** with a simple reactive workflow in a dev branch
3. **Deploy** Ollama to your runners (via Packer/Terraform)
4. **Create** your first production agentic workflow
5. **Monitor** execution and iterate

Need help? Check [AGENTIC_WORKFLOWS_EXAMPLES.md](./AGENTIC_WORKFLOWS_EXAMPLES.md) for copy-paste templates.
