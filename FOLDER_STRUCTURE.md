# Elite Folder Structure Reference

## Root Directory Layout (Max 5 Levels Deep)

```
self-hosted-runner/
├── .github/              # GitHub workflows, actions, issue templates
├── .ssh/                 # SSH keys (gitignored)
├── .credentials/         # Credential files (gitignored)
├── .git/                 # Git repository internals
├── .githooks/            # Git hooks configuration
├── .husky/               # Husky pre-commit hooks
│
├── api/                  # REST API microservices
├── backend/              # Backend services & APIs
├── frontend/             # Frontend UI applications
├── nexusshield/          # NexusShield product code
│
├── infra/                # Infrastructure-as-Code (5 levels max)
│   ├── terraform/        # Terraform configurations
│   ├── kubernetes/       # Kubernetes manifests
│   ├── docker/           # Docker & container setup
│   └── credentials/      # Credential templates (non-secret)
│
├── scripts/              # Automation scripts (5 levels max)
│   ├── deployment/       # Deployment automation (41 scripts)
│   ├── provisioning/     # Credential provisioning (10 scripts)
│   ├── automation/       # Orchestration workflows (16 scripts)
│   └── utilities/        # Helper/utility scripts (30 scripts)
│
├── tests/                # Test automation, test suites
├── monitoring/           # Observability, Prometheus, Grafana
│
├── docs/                 # Documentation hub (5 levels max)
│   ├── governance/       # Governance standards & rules (2 files)
│   ├── runbooks/         # Operational runbooks (3 files)
│   ├── deployment/       # Deployment guides (7 files)
│   ├── architecture/     # Architecture & design docs
│   └── archive/          # Historical reports (165 files)
│
├── operations/           # Operational procedures (5 levels max)
│   ├── playbooks/        # Operational playbooks
│   └── troubleshooting/  # Troubleshooting guides
│
├── config/               # Configuration files
│   ├── docker-compose.yml files
│   ├── .env, .env.example
│   └── system configs
│
├── logs/                 # Runtime logs (gitignored, 49 files)
├── artifacts-archive/    # Historical artifacts
├── runners/              # GitHub Actions self-hosted runners
├── monitoring/           # Monitoring & observability
├── origin/               # Origin/source files
├── repairs/              # Repair/migration scripts
│
└── 📋 Config Files (ROOT ONLY)
    ├── .env              # Environment variables (gitignored)
    ├── .env.example      # Environment template
    ├── .gitignore        # Git ignore rules
    ├── FOLDER_STRUCTURE.md (this file)
    └── .instructions.md  # Copilot behavior enforcement
```

## Directory Purpose & Ownership

| Directory | Purpose | Max Depth | Max Files | Owner |
|-----------|---------|-----------|-----------|-------|
| `docs/governance/` | Governance standards & policies | 2 | 10 | Platform |
| `docs/deployment/` | Deployment guides & runbooks | 2 | 20 | DevOps |
| `docs/runbooks/` | Operational runbooks | 2 | 30 | Ops |
| `docs/archive/` | Historical reports (immutable) | 2 | Unlimited | Archive |
| `scripts/deployment/` | Deployment automation | 3 | 50 | DevOps |
| `scripts/provisioning/` | Credential provisioning | 3 | 30 | Security |
| `scripts/automation/` | Orchestration workflows | 3 | 50 | Automation |
| `infra/terraform/` | Terraform IaC | 4 | 200 | Platform |
| `infra/kubernetes/` | Kubernetes configs | 4 | 100 | Ops |

## File Organization Rules (ENFORCED)

✅ **DO THIS:**
- Place related files together in subdirectories
- Use descriptive folder names (lowercase, hyphenated)
- Keep config files in `config/` folder
- Archive old files in `docs/archive/`
- Organize scripts by function (deployment, provisioning, etc.)
- Use max 5 subdirectory levels

❌ **DON'T DO THIS:**
- Loose files in root directory (except .env, .gitignore, .instructions.md)
- 6+ subdirectory levels deep
- Random folder names without purpose
- Mixed concerns (deployment + provisioning in same folder)
- Duplicate files across folders
- Stale/legacy files in active directories

## Existing Status (After Organization)

✓ 165 historical reports archived (docs/archive/)
✓ 97 scripts organized (BASE64_BLOB_REDACTED)
✓ 10 governance & documentation files organized (docs/governance/, docs/deployment/, docs/runbooks/)
✓ 2 governance rules established (docs/governance/)
✓ 49 log files organized (logs/)
✓ Root directory cleaned (4 files only: .env, .env.example, .gitignore, .instructions.md)

## Adding New Files

When creating new files, follow this decision tree:

1. **Is it code?** → Place in `api/`, `backend/`, `frontend/`, `nexusshield/`, or `infra/`
2. **Is it a script?** → Place in `scripts/{deployment|provisioning|automation|utilities}/`
3. **Is it documentation?** → Place in `docs/{governance|deployment|runbooks|architecture}/`
4. **Is it a config file?** → Place in `config/`
5. **Is it old/historical?** → Place in `docs/archive/`
6. **Is it a test?** → Place in `tests/`
7. **Is it monitoring/observability?** → Place in `monitoring/`

## How to Enforce This Structure

See `.instructions.md` for Copilot behavior enforcement rules.

---
**Status:** ✅ ELITE ORGANIZATION COMPLETE (2026-03-10)
**Last Updated:** 2026-03-10
**Enforcement:** Automated via .instructions.md & GitHub Actions
