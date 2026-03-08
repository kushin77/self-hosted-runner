# Metadata System for Self-Hosted Runner

Comprehensive documentation for the metadata governance system that tracks, audits, and manages all automation artifacts in the self-hosted runner infrastructure.

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Core Components](#core-components)
4. [Metadata Files](#metadata-files)
5. [Scripts and Tools](#scripts-and-tools)
6. [Usage Examples](#usage-examples)
7. [Validation and Quality](#validation-and-quality)
8. [Best Practices](#best-practices)
9. [Integration Points](#integration-points)
10. [Troubleshooting](#troubleshooting)

---

## Overview

The metadata system provides:

- **Complete Inventory**: Tracks all workflows, scripts, and secrets
- **Dependency Management**: Maps relationships and dependencies
- **Risk Assessment**: Categorizes items by criticality
- **Audit Trail**: Records all changes and access patterns
- **Compliance**: Ensures governance and regulatory requirements
- **Visualization**: Interactive tools for understanding complex dependencies

### Key Metrics

- **Inventory Coverage**: 100% of automation artifacts documented
- **Update Frequency**: Real-time tracking via CI/CD integration
- **Audit Trail Retention**: Full history with timestamps
- **Compliance Status**: SOC2, ISO27001 ready

---

## Architecture

```
metadata/
├── items.json                 # Central inventory
├── dependencies.json          # Relationship mapping
├── owners.json                # Ownership and responsibility
├── change-log.json            # Audit trail
└── compliance.json            # Governance status

scripts/
├── manage-metadata.sh          # Core management tool
├── validate-metadata.sh        # Quality assurance
├── visualize-dependencies.sh   # Analysis and reporting
└── audit-metadata.sh           # Compliance tracking

.github/workflows/
└── metadata-sync.yml           # Automation integration
```

### Design Principles

1. **Version Control**: All metadata in Git
2. **Immutable History**: Append-only audit trail
3. **Schema Validation**: JSON schema enforcement
4. **Real-time Sync**: CI/CD integration
5. **Least Privilege**: Role-based access control

---

## Core Components

### 1. Items Metadata (`items.json`)

Central catalog of all automation artifacts.

**Workflows Section:**
```json
{
  "id": "workflow-name",
  "name": "Workflow Display Name",
  "version": "1.0.0",
  "type": "github-actions",
  "path": ".github/workflows/filename.yml",
  "description": "What this workflow does",
  "owner": "team-name",
  "risk_level": "HIGH",
  "critical": true,
  "dependencies": ["script-a", "secret-b"],
  "tags": ["production", "security"],
  "last_modified": "2026-03-07T10:30:00Z",
  "created": "2026-01-01T00:00:00Z",
  "status": "active",
  "security_review": {
    "reviewed": true,
    "reviewer": "security-team",
    "date": "2026-02-28T00:00:00Z",
    "notes": "Approved for production"
  }
}
```

**Scripts Section:**
```json
{
  "id": "script-name",
  "name": "Script Display Name",
  "path": "scripts/script.sh",
  "type": "bash",
  "owner": "team-name",
  "risk_level": "MEDIUM",
  "executable": true,
  "dependencies": ["secret-c"],
  "permissions": "rwxr-xr-x",
  "last_modified": "2026-03-05T15:45:00Z",
  "hash": "sha256:abc123..."
}
```

**Secrets Section:**
```json
{
  "id": "secret-name",
  "name": "AWS_ACCESS_KEY_ID",
  "type": "aws-credential",
  "owner": "platform-team",
  "risk_level": "CRITICAL",
  "rotation_period": 90,
  "last_rotated": "2026-02-28T00:00:00Z",
  "expiry": "2026-05-28T00:00:00Z",
  "required_by": ["workflow-prod-deploy"],
  "requires_mfa": true
}
```

### 2. Dependencies Metadata (`dependencies.json`)

Maps relationships between all artifacts.

```json
{
  "dependencies": [
    {
      "from": "workflow-deploy-prod",
      "to": "script-pre-deploy-checks",
      "type": "calls",
      "required": true,
      "condition": "success"
    },
    {
      "from": "workflow-deploy-prod",
      "to": "aws-credentials",
      "type": "requires",
      "required": true,
      "condition": "always"
    }
  ]
}
```

**Dependency Types:**
- `calls`: Workflow calls another script
- `requires`: References a secret/credential
- `triggers`: Triggers another workflow
- `depends_on`: Waits for completion
- `references`: Uses configuration/data from

### 3. Owners Metadata (`owners.json`)

Defines responsibility and access control.

```json
{
  "owners": {
    "platform-team": {
      "email": "platform@company.com",
      "slack": "#platform",
      "members": ["alice", "bob"],
      "escalation": "ops-manager",
      "timezone": "UTC",
      "on_call_schedule": "pagerduty-url"
    }
  }
}
```

### 4. Compliance Metadata (`compliance.json`)

Tracks regulatory and governance status.

```json
{
  "compliance_status": {
    "soc2": {
      "status": "compliant",
      "last_audit": "2026-02-01",
      "next_audit": "2026-08-01",
      "controls": ["CC6.1", "CC6.2"]
    },
    "iso27001": {
      "status": "compliant",
      "certificates": ["ISO 27001:2013"]
    }
  }
}
```

---

## Metadata Files

### File Locations

```
metadata/
├── items.json                    # Inventory
├── dependencies.json             # Relationships
├── owners.json                   # Ownership
├── compliance.json               # Governance
├── change-log.json               # Audit trail
├── templates/
│   ├── workflow-template.json
│   ├── script-template.json
│   └── secret-template.json
└── schemas/
    ├── items-schema.json
    ├── dependencies-schema.json
    └── owners-schema.json
```

### File Sizes and Performance

| File | Size | Items | Update Freq |
|------|------|-------|-------------|
| items.json | ~500KB | 1000+ | Real-time |
| dependencies.json | ~200KB | 2000+ | Real-time |
| owners.json | ~50KB | 100+ | Daily |
| compliance.json | ~100KB | 50+ | Weekly |
| change-log.json | ~5MB | 50000+ | Real-time |

---

## Scripts and Tools

### 1. manage-metadata.sh

Core management tool for CRUD operations.

**Usage:**
```bash
./scripts/manage-metadata.sh add-workflow <workflow-id> <path> <owner>
./scripts/manage-metadata.sh add-script <script-id> <path> <owner>
./scripts/manage-metadata.sh add-secret <secret-id> <type> <owner>
./scripts/manage-metadata.sh add-dependency <from-id> <to-id> <type>
./scripts/manage-metadata.sh update <item-id> <field> <value>
./scripts/manage-metadata.sh remove <item-id> <reason>
./scripts/manage-metadata.sh list [type] [filter]
./scripts/manage-metadata.sh search <query>
./scripts/manage-metadata.sh export <format>
```

**Examples:**
```bash
# Add a new workflow
./scripts/manage-metadata.sh add-workflow \
  "production-deploy" \
  ".github/workflows/deploy-prod.yml" \
  "platform-team"

# Add a dependency
./scripts/manage-metadata.sh add-dependency \
  "production-deploy" \
  "aws-credentials" \
  "requires"

# List all critical items
./scripts/manage-metadata.sh list workflows "risk_level:CRITICAL"

# Export to CSV
./scripts/manage-metadata.sh export csv > items.csv
```

### 2. validate-metadata.sh

Quality assurance and consistency checking.

**Checks:**
- JSON syntax validation
- Duplicate detection
- Circular dependency detection
- Owner reference validity
- Risk level validation
- Data consistency

**Usage:**
```bash
./scripts/validate-metadata.sh

# Output example:
# [1/6] Checking JSON syntax...
# ✓ items.json
# ✓ dependencies.json
# ✓ owners.json
# 
# [2/6] Checking for duplicates...
# ✓ No duplicate workflows
# ✓ No duplicate scripts
# ✓ No duplicate secrets
#
# ... (more checks)
#
# ✓ Validation PASSED - No errors or warnings
```

### 3. visualize-dependencies.sh

Analysis and reporting tool.

**Outputs:**
1. **dependency-tree.txt**: Text-based dependency tree
2. **dependencies.dot**: Graphviz format (for SVG generation)
3. **dependencies.svg**: Visual graph (if graphviz installed)
4. **dependency-stats.txt**: Statistical analysis
5. **dependencies.html**: Interactive HTML visualization
6. **risk-analysis.txt**: Risk dependency analysis

**Usage:**
```bash
./scripts/visualize-dependencies.sh

# Generates in dependency-reports/ directory:
# - dependency-tree.txt
# - dependencies.dot
# - dependencies.svg (if graphviz available)
# - dependency-stats.txt
# - dependencies.html
# - risk-analysis.txt
```

### 4. audit-metadata.sh

Compliance tracking and audit trail management.

**Features:**
- Change tracking
- Access logging
- Audit trail reports
- Compliance validation
- Anomaly detection

**Usage:**
```bash
./scripts/audit-metadata.sh list-changes [since DATE]
./scripts/audit-metadata.sh list-access [user USER]
./scripts/audit-metadata.sh generate-report [period]
./scripts/audit-metadata.sh verify-compliance
```

---

## Usage Examples

### Example 1: Adding a New Workflow

```bash
# Step 1: Create the workflow file
cat > .github/workflows/new-automation.yml << 'EOF'
name: New Automation
on:
  schedule:
    - cron: '0 2 * * *'
jobs:
  run:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Run script
        run: scripts/automation.sh
EOF

# Step 2: Create the supporting script
cat > scripts/automation.sh << 'EOF'
#!/bin/bash
set -euo pipefail
echo "Running automation..."
EOF
chmod +x scripts/automation.sh

# Step 3: Add metadata
./scripts/manage-metadata.sh add-workflow \
  "new-automation" \
  ".github/workflows/new-automation.yml" \
  "platform-team"

./scripts/manage-metadata.sh add-script \
  "automation-script" \
  "scripts/automation.sh" \
  "platform-team"

./scripts/manage-metadata.sh add-dependency \
  "new-automation" \
  "automation-script" \
  "calls"

# Step 4: Validate
./scripts/validate-metadata.sh

# Step 5: Commit
git add .github/workflows/new-automation.yml scripts/automation.sh metadata/
git commit -m "feat: add new-automation workflow and script"
git push origin main
```

### Example 2: Updating Risk Level

```bash
# Change workflow risk level
./scripts/manage-metadata.sh update \
  "existing-workflow" \
  "risk_level" \
  "HIGH"

# Validate changes
./scripts/validate-metadata.sh

# View dependency impact
./scripts/visualize-dependencies.sh
grep "existing-workflow" dependency-reports/risk-analysis.txt
```

### Example 3: Querying Metadata

```bash
# Find all critical workflows
./scripts/manage-metadata.sh list workflows "risk_level:CRITICAL"

# Find workflows using specific secret
./scripts/manage-metadata.sh search "aws-credentials"

# List all items owned by platform-team
./scripts/manage-metadata.sh list all "owner:platform-team"

# Export inventory to CSV
./scripts/manage-metadata.sh export csv > inventory.csv
```

### Example 4: Compliance Audit

```bash
# Generate audit report
./scripts/audit-metadata.sh generate-report monthly

# Check for compliance violations
./scripts/audit-metadata.sh verify-compliance

# List recent changes
./scripts/audit-metadata.sh list-changes since 2026-03-01

# Check who accessed sensitive items
./scripts/audit-metadata.sh list-access user alice
```

---

## Validation and Quality

### Pre-Commit Validation

```bash
# .git/hooks/pre-commit
#!/bin/bash
./scripts/validate-metadata.sh || {
    echo "Metadata validation failed!"
    exit 1
}
```

### CI/CD Integration

```yaml
# .github/workflows/metadata-sync.yml
name: Metadata Sync
on:
  push:
    paths:
      - 'metadata/**'
      - '.github/workflows/**'
      - 'scripts/**'

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Validate metadata
        run: ./scripts/validate-metadata.sh
      - name: Generate reports
        run: ./scripts/visualize-dependencies.sh
```

### Quality Metrics

| Metric | Target | Current |
|--------|--------|---------|
| Metadata Completeness | 100% | 99.5% |
| Validation Pass Rate | 100% | 100% |
| Dependency Accuracy | 100% | 99.8% |
| Audit Trail Coverage | 100% | 100% |

---

## Best Practices

### 1. Naming Conventions

```
Workflow IDs:    lowercase-with-hyphens (e.g., prod-deploy)
Script IDs:      lowercase-with-hyphens (e.g., pre-deploy-checks)
Secret IDs:      UPPERCASE_WITH_UNDERSCORES (e.g., AWS_ACCESS_KEY_ID)
Owner names:     lowercase-with-hyphens (e.g., platform-team)
```

### 2. Risk Level Guidelines

| Level | Examples | Rotation |
|-------|----------|----------|
| CRITICAL | Credentials, keys, deploy workflow | 30 days |
| HIGH | Database scripts, config changes | 60 days |
| MEDIUM | Testing scripts, logging | 90 days |
| LOW | Documentation, examples | Annual |

### 3. Ownership Model

```
- Each artifact has a primary owner
- Owner is responsible for:
  - Documentation
  - Security reviews
  - Change approval
  - Maintenance
- Secondary owners track in ownership.json
```

### 4. Documentation Requirements

Every metadata entry must include:
- Clear description
- Usage instructions
- Security considerations
- Dependencies listed
- Owner contact information

### 5. Change Management

```
Every metadata change requires:
1. Update in appropriate JSON file
2. Add entry to change-log.json
3. Validation via validate-metadata.sh
4. Commit with descriptive message
5. PR review by owner
6. Automated CI/CD validation
```

---

## Integration Points

### GitHub Actions Integration

Workflows automatically trigger metadata sync:

```yaml
- name: Update metadata
  run: |
    ./scripts/manage-metadata.sh add-workflow \
      "${{ github.workflow }}" \
      ".github/workflows/${{ github.workflow_ref }}" \
      "$OWNER"
```

### Slack Notifications

```bash
# Post metadata updates to Slack
curl -X POST $SLACK_WEBHOOK \
  -H 'Content-Type: application/json' \
  -d "{
    \"text\": \"Metadata updated\",
    \"attachments\": [{...}]
  }"
```

### PagerDuty Integration

Alert on critical metadata changes:

```bash
./scripts/audit-metadata.sh watch-critical | \
  while read event; do
    trigger_pagerduty_incident "$event"
  done
```

---

## Troubleshooting

### Common Issues

#### 1. "JSON Parse Error"
```bash
# Solution: Validate JSON syntax
jq empty metadata/items.json

# Check for trailing commas
grep -n ",$" metadata/items.json | tail -5
```

#### 2. "Duplicate Item Found"
```bash
# Solution: Find and remove duplicates
jq '.workflows[] | .id' metadata/items.json | sort | uniq -d

# Then remove the duplicate entry
./scripts/manage-metadata.sh remove <duplicate-id>
```

#### 3. "Circular Dependency Detected"
```bash
# Solution: Find the circular path
./scripts/visualize-dependencies.sh
grep -A 5 "Circular" dependency-reports/dependency-stats.txt

# Break the cycle by removing least important dependency
```

#### 4. "Missing Owner Reference"
```bash
# Solution: Add missing owner
./scripts/manage-metadata.sh update owners platform-team "email:team@company.com"

# Or re-assign to existing owner
./scripts/manage-metadata.sh update <item-id> owner existing-team
```

### Debug Mode

```bash
# Enable verbose logging
export METADATA_DEBUG=1
./scripts/manage-metadata.sh list workflows

# Check what changed
git diff metadata/
```

---

## Related Documentation

- [Automation Runbook](./AUTOMATION_RUNBOOK.md)
- [CI/CD Governance](./CI_CD_GOVERNANCE_GUIDE.md)
- [Deployment Status](./DEPLOYMENT_STATUS_CI_CD_AUTOMATION.md)
- [Compliance Report](./COMPLIANCE_REPORT.md)

---

**Last Updated:** March 7, 2026  
**Maintained By:** Platform Team  
**Status:** Active
