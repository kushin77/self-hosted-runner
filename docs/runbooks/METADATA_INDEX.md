# Metadata Governance System - Complete Index

> **Status:** Production Ready | **Last Updated:** March 8, 2026 | **Version:** 1.0.0

## Overview

This is a comprehensive metadata governance system for the self-hosted runner automation infrastructure. It provides complete inventory tracking, dependency management, risk assessment, audit trails, and compliance verification.

### Quick Access

| Document | Purpose | Read Time |
|----------|---------|-----------|
| [Quick Start](METADATA_QUICK_START.md) | Get started in 5 minutes | 5 min |
| [System README](METADATA_SYSTEM_README.md) | Complete documentation | 20 min |
| This Index | Navigation and overview | 3 min |

---

## System Components

### 📊 Metadata Files

Located in `metadata/` directory:

```
metadata/
├── items.json              # Inventory of workflows, scripts, secrets
├── dependencies.json       # Relationships between items
├── owners.json             # Ownership and team information
├── compliance.json         # Compliance and audit status
├── change-log.json         # Full audit trail of changes
├── access-log.json         # Access and usage logs
├── templates/              # JSON templates for new items
├── schemas/                # JSON schema validation
└── reports/                # Generated reports directory
```

**Key Statistics:**
- **Workflows:** 3 tracked
- **Scripts:** 3 tracked
- **Secrets:** 3 tracked
- **Dependencies:** Multiple managed relationships
- **Change Log Entries:** Full history
- **Compliance Status:** Verified regularly

### 🛠️ Scripts and Tools

Located in `scripts/` directory:

#### 1. **manage-metadata.sh** (18 KB)
Core CRUD operations and inventory management.

| Command | Purpose |
|---------|---------|
| `add-workflow` | Register new GitHub Actions workflow |
| `add-script` | Register new script file |
| `add-secret` | Register credential/secret |
| `add-dependency` | Create relationships between items |
| `update` | Modify item properties |
| `remove` | Delete item from inventory |
| `list` | Display items (filtered by type) |
| `search` | Find items by name or path |
| `export` | Export inventory (JSON/CSV) |

**Quick Examples:**
```bash
./scripts/manage-metadata.sh add-workflow my-workflow .github/workflows/my.yml team-name CRITICAL
./scripts/manage-metadata.sh list workflows
./scripts/manage-metadata.sh search "production"
./scripts/manage-metadata.sh export csv > inventory.csv
```

#### 2. **validate-metadata.sh** (6 KB)
Quality assurance and consistency checking.

**Checks Performed:**
- ✓ JSON syntax validation
- ✓ Duplicate detection
- ✓ Circular dependency detection
- ✓ Owner reference validation
- ✓ Risk level validation
- ✓ Data consistency verification

**Usage:**
```bash
./scripts/validate-metadata.sh
# Output: ✓ Validation PASSED - No errors or warnings
```

#### 3. **visualize-dependencies.sh** (9 KB)
Dependency analysis and visualization.

**Generates:**
- Text-based dependency tree
- Graphviz DOT format (for SVG)
- Interactive HTML visualization
- Statistical analysis
- Risk dependency analysis

**Usage:**
```bash
./scripts/visualize-dependencies.sh
# Generates dependency-reports/ with multiple formats
```

#### 4. **audit-metadata.sh** (15 KB)
Compliance tracking and audit management.

| Command | Purpose |
|---------|---------|
| `list-changes` | View change history |
| `list-access` | View access patterns |
| `generate-report` | Create audit report |
| `verify-compliance` | Check compliance status |
| `detect-anomalies` | Find unusual patterns |

**Usage:**
```bash
./scripts/audit-metadata.sh verify-compliance
./scripts/audit-metadata.sh list-changes since 2026-03-01
./scripts/audit-metadata.sh generate-report monthly
```

### 🤖 GitHub Actions Integration

**Workflow:** `.github/workflows/metadata-sync.yml`

Automatically validates and syncs metadata on:
- Push to relevant paths
- Daily schedule (2 AM UTC)
- Manual trigger via `workflow_dispatch`

**Tasks:**
- Runs metadata validation
- Verifies compliance
- Detects anomalies
- Generates reports
- Commits updates
- Notifies on issues

---

## Getting Started

### 1. First-Time Setup (2 minutes)

```bash
# Verify installation
cd /path/to/self-hosted-runner
ls -la scripts/{manage,validate,visualize,audit}-metadata.sh
ls -la metadata/

# Test basic command
./scripts/manage-metadata.sh list workflows
```

### 2. Add Your First Item (3 minutes)

```bash
# View existing items
./scripts/manage-metadata.sh list workflows

# Create new workflow
./scripts/manage-metadata.sh add-workflow \
  my-new-workflow \
  .github/workflows/my-new.yml \
  platform-team \
  HIGH

# Validate
./scripts/validate-metadata.sh

# Commit
git add metadata/ .github/workflows/my-new.yml
git commit -m "feat: add my-new-workflow"
git push
```

### 3. Create Dependencies (2 minutes)

```bash
# Link workflow to script
./scripts/manage-metadata.sh add-dependency \
  my-new-workflow \
  my-script \
  calls

# Link script to secret
./scripts/manage-metadata.sh add-dependency \
  my-script \
  aws-credentials \
  requires

# Visualize
./scripts/visualize-dependencies.sh
open dependency-reports/dependencies.html
```

---

## Common Workflows

### Scenario 1: Adding Production Deployment Workflow

```bash
# 1. Create workflow and script files
# 2. Add to metadata
./scripts/manage-metadata.sh add-workflow prod-deploy ... CRITICAL
./scripts/manage-metadata.sh add-script pre-deploy-checks ... HIGH

# 3. Create dependencies
./scripts/manage-metadata.sh add-dependency prod-deploy pre-deploy-checks calls
./scripts/manage-metadata.sh add-dependency pre-deploy-checks aws-creds requires
./scripts/manage-metadata.sh add-dependency prod-deploy aws-creds requires

# 4. Validate everything
./scripts/validate-metadata.sh
./scripts/audit-metadata.sh verify-compliance

# 5. Commit and push
git add metadata/ .github/workflows/ scripts/
git commit -m "feat: production deployment workflow with dependencies"
git push origin main
```

### Scenario 2: Rotating Credentials

```bash
# 1. List all secrets
./scripts/manage-metadata.sh list secrets

# 2. Update rotation date
./scripts/manage-metadata.sh update aws-access-key last_rotated "2026-03-08T00:00:00Z"

# 3. Check compliance
./scripts/audit-metadata.sh verify-compliance

# 4. Generate report
./scripts/audit-metadata.sh generate-report
```

### Scenario 3: Onboarding New Team

```bash
# 1. Add team to owners
# Edit metadata/owners.json or use update command

# 2. Add team's workflows
./scripts/manage-metadata.sh add-workflow team-workflow ... new-team HIGH
./scripts/manage-metadata.sh add-script team-script ... new-team MEDIUM

# 3. Validate
./scripts/validate-metadata.sh

# 4. Generate report for team
./scripts/visualize-dependencies.sh
```

### Scenario 4: Compliance Audit

```bash
# 1. Verify compliance
./scripts/audit-metadata.sh verify-compliance

# 2. Check anomalies
./scripts/audit-metadata.sh detect-anomalies

# 3. Generate report
./scripts/audit-metadata.sh generate-report monthly

# 4. Review access logs
./scripts/audit-metadata.sh list-access

# 5. Upload report
git add metadata/reports/
git commit -m "docs: monthly compliance report"
git push origin main
```

---

## Understanding the Data Model

### Items.json Structure

```json
{
  "workflows": [
    {
      "id": "workflow-id",
      "name": "Display Name",
      "path": ".github/workflows/file.yml",
      "owner": "team-name",
      "risk_level": "HIGH|CRITICAL|MEDIUM|LOW",
      "critical": true|false,
      "created": "2026-03-08T...",
      "last_modified": "2026-03-08T...",
      "status": "active|inactive|deprecated",
      "dependencies": [],
      "security_review": {
        "reviewed": true|false,
        "reviewer": "reviewer-name",
        "date": "2026-03-08T...",
        "notes": "Review notes"
      }
    }
  ]
}
```

### Dependencies.json Structure

```json
{
  "dependencies": [
    {
      "from": "workflow-or-script-id",
      "to": "script-or-secret-id",
      "type": "calls|requires|triggers|depends_on|references",
      "required": true|false,
      "condition": "success|always|failure"
    }
  ]
}
```

### Risk Levels

| Level | Examples | Rotation | MFA |
|-------|----------|----------|-----|
| **CRITICAL** | Credentials, deploy keys, prod workflows | 30 days | Required |
| **HIGH** | Database scripts, config changes | 60 days | Recommended |
| **MEDIUM** | Testing scripts, staging workflows | 90 days | Optional |
| **LOW** | Documentation, examples, dev tools | Annual | Not required |

---

## Integration Points

### GitHub Actions

Metadata automatically updates when:
- Workflow files change
- Scripts are modified
- Secrets are rotated
- Dependencies are added

### Slack Integration (Optional)

```bash
# Post notifications on changes
curl -X POST $SLACK_WEBHOOK \
  -d '{"text": "Metadata updated: ..."}'
```

### CI/CD Pipeline

Metadata validation is a required gate:
```yaml
- name: Validate metadata
  run: ./scripts/validate-metadata.sh || exit 1
```

---

## Best Practices

### 1. Naming Conventions
- **Workflows:** `lowercase-with-hyphens` (e.g., `prod-deploy`)
- **Scripts:** `lowercase-with-hyphens` (e.g., `pre-deploy-checks`)
- **Secrets:** `UPPERCASE_WITH_UNDERSCORES` (e.g., `AWS_ACCESS_KEY`)
- **Owners:** `lowercase-with-hyphens` (e.g., `platform-team`)

### 2. Documentation
Every metadata entry must include:
- Clear description
- Usage instructions
- Owner contact information
- Dependencies listed
- Security considerations

### 3. Change Management
```
1. Update JSON file
2. Run ./scripts/validate-metadata.sh
3. Create a Draft issue
4. Review and approve
5. Merge to main
6. Automated sync runs
```

### 4. Regular Audits
```bash
# Weekly
./scripts/audit-metadata.sh verify-compliance
./scripts/audit-metadata.sh detect-anomalies

# Monthly  
./scripts/audit-metadata.sh generate-report monthly

# Quarterly
# Full review and update
```

---

## Troubleshooting

### Issue: JSON Parse Error

```bash
# Validate syntax
jq empty metadata/items.json

# Find problem
cat -n metadata/items.json | grep -E ',\s*}|,\s*]'

# Fix formatting
jq '.' metadata/items.json > tmp && mv tmp metadata/items.json
```

### Issue: Duplicate Items

```bash
# Find duplicates
jq '.workflows[] | .id' metadata/items.json | sort | uniq -d

# Remove and recreate
./scripts/manage-metadata.sh remove <id>
./scripts/manage-metadata.sh add-workflow ...
```

### Issue: Compliance Failures

```bash
# Check what failed
./scripts/audit-metadata.sh verify-compliance

# Review specific section
jq '.workflows[] | select(.risk_level == "CRITICAL")' metadata/items.json

# Fix issues and retry
./scripts/validate-metadata.sh
```

---

## Performance & Scalability

| Metric | Current | Target |
|--------|---------|--------|
| Items | 9 | 1000+ |
| Dependencies | Multiple | 2000+ |
| Validation Time | <1s | <5s |
| Report Generation | <5s | <10s |
| Change Log Size | Growing | Archive at 50K entries |

### Optimization Tips

```bash
# Large dataset performance
time ./scripts/validate-metadata.sh        # Measure performance
time ./scripts/visualize-dependencies.sh   

# Archive old change logs
jq '.changes | length' metadata/change-log.json
# Archive when >50000 entries
```

---

## Resources

### Documentation Files

| File | Purpose |
|------|---------|
| [METADATA_QUICK_START.md](METADATA_QUICK_START.md) | Quick start guide |
| [METADATA_SYSTEM_README.md](METADATA_SYSTEM_README.md) | Complete system documentation |
| [This File](METADATA_INDEX.md) | Navigation hub (you are here) |

### Generated Reports

Located in `dependency-reports/`:
- `dependency-tree.txt` - Text-based tree view
- `dependencies.html` - Interactive visualization
- `dependencies.dot` - Graphviz format
- `dependency-stats.txt` - Statistics
- `risk-analysis.txt` - Risk assessment

### Related Documents

- [Automation Runbook](../../scripts/automation/AUTOMATION_RUNBOOK.md)
- [CI/CD Governance Guide](CI_CD_GOVERNANCE_GUIDE.md)
- [Compliance Report](../archive/completion-reports/COMPLIANCE_REPORT.md)

---

## Support & Maintenance

### Getting Help

1. **Quick Questions:** See [METADATA_QUICK_START.md](METADATA_QUICK_START.md)
2. **Full Documentation:** See [METADATA_SYSTEM_README.md](METADATA_SYSTEM_README.md)
3. **Tool Help:**
   ```bash
   ./scripts/manage-metadata.sh --help
   ./scripts/validate-metadata.sh --help
   ./scripts/audit-metadata.sh --help
   ```

### Reporting Issues

Create a GitHub issue with:
- What command you ran
- Current output
- Expected output
- Metadata files (if safe to share)

### Contributing

To improve the system:
1. Make changes to scripts or documentation
2. Test thoroughly
3. Create a Draft issue
4. Get review from platform team
5. Merge and deploy

---

## Roadmap

### Completed ✓
- [x] Core CRUD operations
- [x] Dependency tracking
- [x] Compliance verification
- [x] Audit trail
- [x] Risk assessment
- [x] Visualization tools
- [x] GitHub Actions integration

### Planned 📋
- [ ] Web UI for management
- [ ] API endpoint for integrations
- [ ] Slack bot commands
- [ ] Automated remediation
- [ ] Historical analytics
- [ ] Machine learning anomaly detection

### Future Ideas 🚀
- [ ] CI/CD platform agnostic
- [ ] Multi-organization support
- [ ] Advanced RBAC
- [ ] Cost attribution
- [ ] Usage analytics

---

## Summary

The metadata governance system provides:

✅ **Complete Inventory** - Track all automation artifacts  
✅ **Dependency Management** - Understand relationships  
✅ **Risk Assessment** - Prioritize critical items  
✅ **Audit Trails** - Full change history  
✅ **Compliance** - Regulatory requirements  
✅ **Visualization** - Interactive reports  
✅ **Automation** - CI/CD integration  

### Next Steps

1. **Read** [METADATA_QUICK_START.md](METADATA_QUICK_START.md)
2. **Try** `./scripts/manage-metadata.sh list`
3. **Add** your first item
4. **Validate** with `./scripts/validate-metadata.sh`
5. **Explore** `dependency-reports/`

---

**System Status:** ✅ Production Ready  
**Last Validation:** March 8, 2026  
**Maintained By:** Platform Team  
**Contact:** platform@company.com
