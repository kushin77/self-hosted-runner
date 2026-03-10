# Elite Status Folder Organization Plan

## Folder Structure (Max 5 levels deep)
```
self-hosted-runner/
├── .github/              # GitHub workflows & actions (existing)
├── .ssh/                 # SSH keys (existing)
├── .credentials/         # Credentials (existing, secured)
├── .git/                 # Git internals (existing)
├── .githooks/            # Git hooks (existing)
├── .husky/               # Husky config (existing)
│
├── api/                  # REST API services (existing)
├── backend/              # Backend services (existing)
├── frontend/             # Frontend services (existing)
├── nexusshield/          # NexusShield product code (existing)
│
├── infra/                # Infrastructure-as-Code (existing)
│   ├── terraform/        # Terraform configurations
│   ├── kubernetes/       # Kubernetes manifests
│   ├── docker/           # Docker configurations
│   └── credentials/      # Credential templates
│
├── scripts/              # Automation & operational scripts (organized)
│   ├── deployment/       # Deployment automation
│   ├── provisioning/     # Credential/service provisioning
│   ├── automation/       # Orchestration workflows
│   └── utilities/        # Helper scripts
│
├── tests/                # Test automation (existing)
├── monitoring/           # Observability & monitoring (existing)
│
├── docs/                 # Documentation hub
│   ├── governance/       # Governance standards & rules
│   ├── runbooks/         # Operational runbooks
│   ├── deployment/       # Deployment guides
│   ├── architecture/     # Architecture documentation
│   └── archive/          # Historical reports (date-stamped)
│
├── operations/           # Operational procedures
│   ├── playbooks/        # Operational playbooks
│   ├── troubleshooting/  # Troubleshooting guides
│   └── runbooks/         # Runbook collection
│
├── config/               # Configuration files
│   ├── env.example       # Environment template
│   ├── docker-compose.yml files
│   └── system configs
│
├── logs/                 # Runtime logs (existing, gitignored)
├── artifacts-archive/    # Historical artifacts (new)
│
├── .env                  # Environment vars (existing)
├── .gitignore            # .gitignore (existing)
└── README.md             # Elite project README
```

## Files to Archive (→ docs/archive/)
- All DEPLOYMENT_*.md files
- All PHASE_*.md files
- All PRODUCTION_*.md files
- All MILESTONE_*.md files
- All FINAL_*.md files
- All EXECUTION_*.md files
- All dated completion reports (2026-03-*)
- Legacy admin/provisioning guides

## Files to Keep in Root
- README.md (main project README)
- .env, .env.example, .gitignore
- Config files: .instructions.md, GIT_GOVERNANCE_STANDARDS.md

## Files to Move to docs/governance/
- GIT_GOVERNANCE_STANDARDS.md
- NO_GITHUB_ACTIONS_POLICY.md
- REPO_DEPLOYMENT_POLICY.md

## Files to Move to docs/deployment/
- CREDENTIAL_PROVISIONING_RUNBOOK.md
- AUTOMATED_TRUNK_DEPLOYMENT_GUIDE.md
- FAILOVER_TEST_PROCEDURES.md
- CREDENTIAL_SECURITY_HARDENING_*.md

## Files to Move to docs/runbooks/
- All operational guides and runbooks
- Phase-specific guides (if active)
- Troubleshooting documents

## Quick Scripts to Keep in Root (only)
- QUICK_START_COMMANDS.sh (→ scripts/utilities/)
- RUN_LOCAL.md (→ docs/deployment/)
- README_DEPLOYMENT_SYSTEM.md (→ docs/deployment/)

## Status: ELITE ORGANIZATION READY
