# 5-System Organizational Framework

**Complete Integration Guide**

---

## Overview

This repository now has a comprehensive organizational system consisting of **5 complementary indices and audit tools** to help developers, operators, and Copilot navigate complexity and reduce errors.

### The 5 Systems

| System | Purpose | Master Index | Audit Tool | Status |
|--------|---------|--------------|------------|--------|
| **1. Secrets** | All credentials and API keys | [SECRETS_INDEX.md](SECRETS_INDEX.md) | `bash scripts/audit-secrets.sh` | ✅ Complete |
| **2. Workflows** | CI/CD and automation | [WORKFLOWS_INDEX.md](WORKFLOWS_INDEX.md) | `bash scripts/audit-workflows.sh` | ✅ Complete |
| **3. Scripts** | Executable scripts | [SCRIPTS_REGISTRY.md](SCRIPTS_REGISTRY.md) | `bash scripts/audit-scripts.sh` | ✅ Complete |
| **4. Errors** | Common problems & solutions | [ERROR_CODES_GUIDE.md](ERROR_CODES_GUIDE.md) | Manual (reference) | ✅ Complete |
| **5. Configuration** | Settings and environment | [CONFIGURATION_GUIDE.md](CONFIGURATION_GUIDE.md) | Manual (reference) | ✅ Complete |

---

## How to Use Each System

### System 1: Secrets Management
**When:** You need to find, add, or validate secrets  
**Start with:** [SECRETS_INDEX.md](SECRETS_INDEX.md)

```bash
# Find what secrets exist
bash scripts/audit-secrets.sh --full

# Search for specific secret
bash scripts/audit-secrets.sh --search "GITHUB_"

# Validate configuration
bash scripts/audit-secrets.sh --validate

# Export for documentation
bash scripts/audit-secrets.sh --json > secrets-export.json
```

**Related files:**
- [DEVELOPER_SECRETS_GUIDE.md](DEVELOPER_SECRETS_GUIDE.md) — Step-by-step guide for adding secrets
- [CONTRIBUTING.md](CONTRIBUTING.md#secrets--credentials) — Secrets rules for contributors

---

### System 2: Workflows Discovery
**When:** You need to find the right workflow or understand CI/CD chains  
**Start with:** [WORKFLOWS_INDEX.md](WORKFLOWS_INDEX.md)

```bash
# List all workflows with details
bash scripts/audit-workflows.sh --full

# Find workflows by category
bash scripts/audit-workflows.sh --category terraform

# Find workflows by trigger type
bash scripts/audit-workflows.sh --trigger schedule

# Show high-complexity workflows
bash scripts/audit-workflows.sh --complex

# Validate workflow files
bash scripts/audit-workflows.sh --validate
```

**Common Questions:**
- **"How do I deploy to production?"** → See [WORKFLOWS_INDEX.md - Deployment Category](WORKFLOWS_INDEX.md#deployment-workflows)
- **"What triggers this workflow?"** → See the table in [WORKFLOWS_INDEX.md](WORKFLOWS_INDEX.md)
- **"Which workflows use this secret?"** → Search WORKFLOWS_INDEX.md for secret name

---

### System 3: Scripts Registry
**When:** You need to find a script, understand dependencies, or audit critical paths  
**Start with:** [SCRIPTS_REGISTRY.md](SCRIPTS_REGISTRY.md)

```bash
# List all scripts with risk assessment
bash scripts/audit-scripts.sh --full

# Find scripts by category
bash scripts/audit-scripts.sh --category deployment

# Show only critical scripts
bash scripts/audit-scripts.sh --critical

# Check script integrity
bash scripts/audit-scripts.sh --validate

# Understand dependencies (which calls which)
bash scripts/audit-scripts.sh --dependencies
```

**Common Questions:**
- **"What's the safest way to deploy?"** → See [SCRIPTS_REGISTRY.md - Most Critical Scripts](SCRIPTS_REGISTRY.md#most-critical-scripts)
- **"Does this script call that script?"** → Use `--dependencies` mode
- **"Can I safely run X?"** → Check risk level (HIGH/CRITICAL = get approval)

---

### System 4: Error Reference
**When:** Something broke and you need to fix it  
**Start with:** [ERROR_CODES_GUIDE.md](ERROR_CODES_GUIDE.md)

```bash
# Search for error by description
grep -i "permission denied" ERROR_CODES_GUIDE.md

# Search for error code
grep "ERR-AWS-001" ERROR_CODES_GUIDE.md
```

**Common Errors:**
- **"Error: Unable to assume role"** → See [ERROR_CODES_GUIDE.md#err-aws-001](ERROR_CODES_GUIDE.md)
- **"GitHub API rate limited"** → See [ERROR_CODES_GUIDE.md#err-runner-005](ERROR_CODES_GUIDE.md)
- **"Terraform lock timeout"** → See [ERROR_CODES_GUIDE.md#err-tf-003](ERROR_CODES_GUIDE.md)

**Each Error Includes:**
- ✅ Exact symptoms to match
- ✅ Root causes (multiple)
- ✅ Diagnostic commands (copy-paste ready)
- ✅ Solutions with estimated fix time

---

### System 5: Configuration Reference
**When:** You need to set up environment, find config files, or check settings  
**Start with:** [CONFIGURATION_GUIDE.md](CONFIGURATION_GUIDE.md)

```bash
# View all required environment variables
grep "✅ Required" CONFIGURATION_GUIDE.md

# Find configuration file location
grep "Database config" CONFIGURATION_GUIDE.md

# Get setup checklist
tail -20 CONFIGURATION_GUIDE.md
```

**Common Tasks:**
- **"How do I set up local development?"** → See [CONFIGURATION_GUIDE.md - Checklist: Environment Setup](CONFIGURATION_GUIDE.md#checklist-environment-setup)
- **"What's the GitHub secret for X?"** → See [CONFIGURATION_GUIDE.md - GitHub Settings](CONFIGURATION_GUIDE.md#github-settings)
- **"How do I configure Terraform?"** → See [CONFIGURATION_GUIDE.md - Terraform Variables](CONFIGURATION_GUIDE.md#terraform-variables)

---

## Decision Trees

### "I need to add something new"

```
Did you add a SECRET?
├─ YES → Update SECRETS_INDEX.md + Run audit-secrets.sh --validate
└─ NO

Did you add a WORKFLOW?
├─ YES → Update WORKFLOWS_INDEX.md + Run audit-workflows.sh --validate
└─ NO

Did you add a SCRIPT?
├─ YES → Update SCRIPTS_REGISTRY.md + Run audit-scripts.sh --validate
└─ NO

Did you find a new ERROR?
├─ YES → Add to ERROR_CODES_GUIDE.md with symptoms + solutions
└─ NO

Did you change CONFIGURATION?
├─ YES → Update CONFIGURATION_GUIDE.md + Document in CONTRIBUTING.md
└─ DONE!
```

### "Something is broken"

```
Error message visible?
├─ YES
│  ├─ Search ERROR_CODES_GUIDE.md for exact message
│  └─ Run diagnostic commands → apply solution
│
└─ NO (silent failure)
   ├─ Is it related to SECRET?
   │  └─ Run: bash scripts/audit-secrets.sh --validate
   │
   ├─ Is WORKFLOW failing?
   │  └─ Check: WORKFLOWS_INDEX.md → Dependencies section
   │
   ├─ Is SCRIPT failing?
   │  └─ Run: bash scripts/audit-scripts.sh --validate
   │
   └─ Is CONFIG issue?
      └─ Check: CONFIGURATION_GUIDE.md → Debugging section
```

### "I want to understand the system"

```
Understanding SECRETS?
└─ Read: SECRETS_INDEX.md → DEVELOPER_SECRETS_GUIDE.md → Run: audit-secrets.sh --full

Understanding WORKFLOWS?
└─ Read: WORKFLOWS_INDEX.md → Dependencies section → WORKFLOWS_INDEX.md + ERROR_CODES_GUIDE.md for common failures

Understanding SCRIPTS?
└─ Read: SCRIPTS_REGISTRY.md → Most Critical Scripts → Run: audit-scripts.sh --dependencies

Understanding ERRORS?
└─ Read: ERROR_CODES_GUIDE.md → Pick an error → See Solutions

Understanding CONFIG?
└─ Read: CONFIGURATION_GUIDE.md → Section matching your need
```

---

## Cross-System Relationships

### How Configurations → Secrets → Workflows → Scripts → Errors

```
┌─ CONFIGURATION_GUIDE.md ─────────────────────────┐
│  Defines: Environment variables, settings        │
│  References: SECRETS_INDEX.md for secret names   │
└──────────────────────┬──────────────────────────┘
                       │
┌─ SECRETS_INDEX.md ───┴──────────────────────────┐
│  Lists: All secrets needed                      │
│  Shows: Which workflows/scripts use each secret │
│  TIP: Used by 195 workflows                     │
└──────────────────────┬──────────────────────────┘
                       │
┌─ WORKFLOWS_INDEX.md ──┴──────────────────────────┐
│  Lists: 197 workflows in 11 categories           │
│  Shows: Which scripts each workflow calls        │
│  Links to: ERROR_CODES_GUIDE.md for debugging   │
└──────────────────────┬──────────────────────────┘
                       │
┌─ SCRIPTS_REGISTRY.md ─┴──────────────────────────┐
│  Lists: 174 scripts in 9 categories              │
│  Shows: Risk levels, dependencies, callers       │
│  Links to: WORKFLOWS_INDEX.md & ERROR codes      │
└──────────────────────┬──────────────────────────┘
                       │
┌─ ERROR_CODES_GUIDE.md ┴──────────────────────────┐
│  Lists: 20+ common errors by system              │
│  Each error: Symptoms → Diagnosis → Solutions    │
│  Includes: Exact commands, fix times             │
└────────────────────────────────────────────────┘
```

---

## Audit Commands Quick Reference

### Discovery Commands

```bash
# Secrets: Find what we have
bash scripts/audit-secrets.sh --full              # All details
bash scripts/audit-secrets.sh --summary           # Just stats

# Workflows: Understand CI/CD
bash scripts/audit-workflows.sh --full            # All workflows
bash scripts/audit-workflows.sh --complex         # High-impact only
bash scripts/audit-workflows.sh --summary         # Statistics

# Scripts: Locate and categorize
bash scripts/audit-scripts.sh --full              # All scripts
bash scripts/audit-scripts.sh --critical          # High-risk only
bash scripts/audit-scripts.sh --summary           # Statistics
```

### Search Commands

```bash
# Find secret
bash scripts/audit-secrets.sh --search "GITHUB_"

# Find workflow
bash scripts/audit-workflows.sh --search "terraform"

# Find script
bash scripts/audit-scripts.sh --search "deploy"
```

### By Category

```bash
# Find workflows by category
bash scripts/audit-workflows.sh --category terraform
bash scripts/audit-workflows.sh --category deployment

# Find scripts by category
bash scripts/audit-scripts.sh --category terraform
bash scripts/audit-scripts.sh --category deployment
```

### Validation Commands

```bash
# Validate all secrets configured
bash scripts/audit-secrets.sh --validate

# Validate all workflows have correct format
bash scripts/audit-workflows.sh --validate

# Validate all scripts have proper shebang and syntax
bash scripts/audit-scripts.sh --validate
```

### Export Commands

```bash
# Export secrets to JSON (for tooling)
bash scripts/audit-secrets.sh --json > secrets.json

# Export workflows to JSON
bash scripts/audit-workflows.sh --json > workflows.json

# Export scripts to JSON
bash scripts/audit-scripts.sh --json > scripts.json

# Parse JSON programmatically
bash scripts/audit-secrets.sh --json | jq '.[] | select(.name == "GITHUB_TOKEN")'
```

---

## Integration With CONTRIBUTING.md

All developers must follow these rules when adding to any system:

### When Adding a Secret
1. Create secret in GitHub → Document in [SECRETS_INDEX.md](SECRETS_INDEX.md)
2. Run: `bash scripts/audit-secrets.sh --validate`
3. Update [CONTRIBUTING.md#secrets](CONTRIBUTING.md#secrets--credentials) if new pattern
4. PR must reference SECRETS_INDEX update

### When Adding a Workflow
1. Create `.github/workflows/xxx.yml` → Document in [WORKFLOWS_INDEX.md](WORKFLOWS_INDEX.md)
2. Run: `bash scripts/audit-workflows.sh --validate`
3. List dependencies in WORKFLOWS_INDEX.md
4. PR must reference WORKFLOWS_INDEX update

### When Adding a Script
1. Create `scripts/xxx.sh` (with error handling!) → Document in [SCRIPTS_REGISTRY.md](SCRIPTS_REGISTRY.md)
2. Run: `bash scripts/audit-scripts.sh --validate`
3. List dependencies and risk level in SCRIPTS_REGISTRY.md
4. PR must reference SCRIPTS_REGISTRY update

### When Finding a New Error
1. Add to [ERROR_CODES_GUIDE.md](ERROR_CODES_GUIDE.md) with:
   - Error code (ERR-SYSTEM-NNN format)
   - Exact symptoms
   - Root causes (multiple)
   - Diagnostic commands
   - Solutions with fix time
2. Reference in relevant workflow/script
3. PR comment: "Added error code ERR-XXX-NNN"

---

## Metrics & Maintenance

### Current Inventory

| System | Count | Audit Tool | Last Update |
|--------|-------|-----------|-------------|
| Secrets | 88 (10 configured) | ✅ Working | Today |
| Workflows | 197 | ✅ Working | Today |
| Scripts | 174 (44 critical) | ✅ Working | Today |
| Error Codes | 20+ | ✅ Reference | Today |
| Config Items | 50+ | ✅ Reference | Today |

### Maintenance Schedule

- **Weekly**: Run `bash scripts/audit-secrets.sh --validate` in CI
- **Weekly**: Run `bash scripts/audit-workflows.sh --validate` in CI
- **Weekly**: Run `bash scripts/audit-scripts.sh --validate` in CI
- **Monthly**: Review ERROR_CODES_GUIDE.md for new patterns
- **Quarterly**: Audit all indices for outdated references

---

## Getting Help

**Which document should I read?**

| Question | Start Here |
|----------|-----------|
| "What secrets exist?" | [SECRETS_INDEX.md](SECRETS_INDEX.md) |
| "How do I add a secret?" | [DEVELOPER_SECRETS_GUIDE.md](DEVELOPER_SECRETS_GUIDE.md) |
| "Which workflow does X?" | [WORKFLOWS_INDEX.md](WORKFLOWS_INDEX.md) |
| "What script does Y?" | [SCRIPTS_REGISTRY.md](SCRIPTS_REGISTRY.md) |
| "Error code Z?" | [ERROR_CODES_GUIDE.md](ERROR_CODES_GUIDE.md) |
| "Config variable?" | [CONFIGURATION_GUIDE.md](CONFIGURATION_GUIDE.md) |
| "I'm stuck!" | [ERROR_CODES_GUIDE.md](ERROR_CODES_GUIDE.md) → Debugging Tools |
| "I'm adding something" | [CONTRIBUTING.md](CONTRIBUTING.md) |

---

## Benefits of This System

✅ **Single Source of Truth** — No more hunting through code/docs  
✅ **Programmatic Discovery** — Audit scripts find anything in seconds  
✅ **Error Prevention** — Centralized patterns prevent copy-paste mistakes  
✅ **Copilot-Friendly** — Clear organization keeps AI assistant focused  
✅ **Developer Experience** — New team members onboard faster  
✅ **Searchable** — `grep` and `bash audit-X.sh --search` find anything  
✅ **Maintainable** — Audit scripts auto-update as code changes  
✅ **Documented** — Every secret, workflow, script, error has context  

---

*Last Updated: March 7, 2026*  
*Next Review: June 7, 2026*  
*Maintained by: DevOps & Infrastructure Team*
