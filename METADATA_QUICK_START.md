# Metadata Management Quick Start

This guide will help you get started with the metadata management system in 5 minutes.

## Table of Contents

1. [Installation & Setup](#installation--setup)
2. [First Steps](#first-steps)
3. [Common Tasks](#common-tasks)
4. [Tips & Tricks](#tips--tricks)
5. [Troubleshooting](#troubleshooting)

---

## Installation & Setup

### Prerequisites

- `jq` (JSON query tool) installed
- Bash shell
- Git access

### Verify Installation

```bash
# Check scripts are executable
ls -la scripts/{manage,validate,visualize,audit}-metadata.sh

# Verify metadata directory exists
ls -la metadata/

# Test with a simple command
./scripts/manage-metadata.sh --help
```

**Expected Output:**
```
Usage: manage-metadata.sh <command> [options]
Commands:
  add-workflow <id> <path> <owner> [risk-level]
  ...
```

---

## First Steps

### Step 1: Add Your First Workflow

Navigate to your repository root and run:

```bash
# Create a simple workflow file first
cat > .github/workflows/hello-world.yml << 'EOF'
name: Hello World
on: push
jobs:
  hello:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - run: echo "Hello from GitHub Actions!"
EOF

# Add metadata for this workflow
./scripts/manage-metadata.sh add-workflow \
  "hello-world" \
  ".github/workflows/hello-world.yml" \
  "platform-team" \
  "LOW"
```

**Output:**
```
✓ Added workflow: hello-world
```

### Step 2: Validate Your Metadata

```bash
./scripts/validate-metadata.sh
```

**Output:**
```
╔════════════════════════════════════════════════════════════╗
║ METADATA VALIDATION
╚════════════════════════════════════════════════════════════╝

[1/6] Checking JSON syntax...
✓ items.json
✓ dependencies.json
[2/6] Checking for duplicates...
✓ No duplicate workflows
...
✓ Validation PASSED - No errors or warnings
```

### Step 3: List Your Items

```bash
./scripts/manage-metadata.sh list workflows
```

**Output:**
```
=== Workflows ===
hello-world [LOW] - platform-team
```

---

## Common Tasks

### Adding a Script

```bash
# Create the script
cat > scripts/deploy.sh << 'EOF'
#!/bin/bash
echo "Deploying..."
EOF
chmod +x scripts/deploy.sh

# Add metadata
./scripts/manage-metadata.sh add-script \
  "deploy-script" \
  "scripts/deploy.sh" \
  "platform-team" \
  "HIGH"

# Verify
./scripts/manage-metadata.sh list scripts
```

### Adding a Secret

```bash
# Add secret metadata
./scripts/manage-metadata.sh add-secret \
  "aws-access-key" \
  "aws-credential" \
  "platform-team"

# Secrets are always CRITICAL risk level
./scripts/manage-metadata.sh list secrets
```

### Creating Dependencies

```bash
# The hello-world workflow depends on the deploy script
./scripts/manage-metadata.sh add-dependency \
  "hello-world" \
  "deploy-script" \
  "calls"

# The deploy script requires AWS credentials
./scripts/manage-metadata.sh add-dependency \
  "deploy-script" \
  "aws-access-key" \
  "requires"

# Verify dependencies
./scripts/visualize-dependencies.sh
```

### Updating Metadata

```bash
# Change a workflow's risk level
./scripts/manage-metadata.sh update \
  "hello-world" \
  "risk_level" \
  "HIGH"

# Verify the change
./scripts/manage-metadata.sh list workflows
```

### Searching Metadata

```bash
# Search for items containing "deploy"
./scripts/manage-metadata.sh search "deploy"

# Output:
# [WORKFLOW] production-deploy
# [SCRIPT] deploy-script
```

### Exporting Data

```bash
# Export as CSV for spreadsheets
./scripts/manage-metadata.sh export csv > inventory.csv

# View in default spreadsheet application
open inventory.csv

# Or export as JSON for integration
./scripts/manage-metadata.sh export json | jq '.'
```

### Checking Compliance

```bash
# Run compliance verification
./scripts/audit-metadata.sh verify-compliance

# Output will show:
# [1/5] Checking item ownership...
# ✓ All workflows have owners
# [2/5] Checking security reviews for critical items...
# ...
# ✓ Compliance Status: FULLY COMPLIANT
```

### Viewing Audit Trail

```bash
# See recent changes
./scripts/audit-metadata.sh list-changes

# See changes since a specific date
./scripts/audit-metadata.sh list-changes since 2026-03-01

# See access patterns
./scripts/audit-metadata.sh list-access

# See specific user's access
./scripts/audit-metadata.sh list-access user alice
```

---

## Tips & Tricks

### Workflow: Adding a Complete Production Workflow

```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OWNER="platform-team"

# 1. Create the workflow file
cat > .github/workflows/prod-deploy.yml << 'EOF'
name: Production Deploy
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - run: ./scripts/pre-deploy-checks.sh
      - run: ./scripts/deploy.sh
EOF

# 2. Create supporting scripts
cat > scripts/pre-deploy-checks.sh << 'EOF'
#!/bin/bash
echo "Running pre-deployment checks..."
EOF
chmod +x scripts/pre-deploy-checks.sh

cat > scripts/deploy.sh << 'EOF'
#!/bin/bash
echo "Deploying to production..."
EOF
chmod +x scripts/deploy.sh

# 3. Add metadata
"$SCRIPT_DIR/manage-metadata.sh" add-workflow \
  "prod-deploy" \
  ".github/workflows/prod-deploy.yml" \
  "$OWNER" \
  "CRITICAL"

"$SCRIPT_DIR/manage-metadata.sh" add-script \
  "pre-deploy-checks" \
  "scripts/pre-deploy-checks.sh" \
  "$OWNER" \
  "HIGH"

"$SCRIPT_DIR/manage-metadata.sh" add-script \
  "deploy" \
  "scripts/deploy.sh" \
  "$OWNER" \
  "CRITICAL"

# 4. Add dependencies
"$SCRIPT_DIR/manage-metadata.sh" add-dependency \
  "prod-deploy" \
  "pre-deploy-checks" \
  "calls"

"$SCRIPT_DIR/manage-metadata.sh" add-dependency \
  "prod-deploy" \
  "deploy" \
  "calls"

"$SCRIPT_DIR/manage-metadata.sh" add-dependency \
  "deploy" \
  "aws-credentials" \
  "requires"

# 5. Validate
"$SCRIPT_DIR/validate-metadata.sh"

echo "✓ Production deployment workflow added and validated!"
```

### Generating Reports

```bash
# Generate a monthly report
./scripts/audit-metadata.sh generate-report monthly

# The report includes:
# - Summary statistics
# - Recent changes
# - Access patterns
# - Compliance status
```

### Automated Daily Validation

The GitHub Actions workflow runs automatically:

```yaml
# This is already configured in .github/workflows/metadata-sync.yml
schedule:
  - cron: '0 2 * * *'  # Daily at 2 AM UTC
```

You can also trigger manually:

```bash
# Push to trigger validation
git push origin main

# Or manually trigger workflow
gh workflow run metadata-sync.yml
```

### Batch Operations

```bash
# Find all CRITICAL items
jq '.workflows[] | select(.risk_level == "CRITICAL")' metadata/items.json

# Update all HIGH items to CRITICAL
jq '.workflows |= map(select(.risk_level == "HIGH") | .risk_level = "CRITICAL")' \
  metadata/items.json > metadata/items.json.tmp
mv metadata/items.json.tmp metadata/items.json

# Validate and commit
./scripts/validate-metadata.sh && \
  git add metadata/ && \
  git commit -m "chore: update risk levels" && \
  git push
```

---

## Troubleshooting

### Problem: "JSON Parse Error"

**Symptoms:**
```
jq: parse error: ...
```

**Solution:**
```bash
# Check file syntax
jq empty metadata/items.json

# Find the problem line (look for trailing commas, missing quotes)
cat -n metadata/items.json | grep -E ',\s*}|,\s*]'

# Use a JSON formatter to fix
jq '.' metadata/items.json > metadata/items.json.tmp
mv metadata/items.json.tmp metadata/items.json
```

### Problem: "Item Already Exists"

**Symptoms:**
```
✗ ERROR: Workflow 'deploy' already exists
```

**Solution:**
```bash
# Check if item exists
jq '.workflows[] | select(.id == "deploy")' metadata/items.json

# Remove it first if needed
./scripts/manage-metadata.sh remove deploy "replaced with newer version"

# Then add the new one
./scripts/manage-metadata.sh add-workflow ...
```

### Problem: "Unknown Owner"

**Symptoms:**
```
⚠ Unknown owner: my-team
```

**Solution:**
```bash
# Check existing owners
jq '.owners | keys' metadata/owners.json

# Add new owner to metadata/owners.json
jq '.owners.["my-team"] = {
  "email": "my-team@company.com",
  "slack": "#my-team",
  "members": []
}' metadata/owners.json > metadata/owners.json.tmp
mv metadata/owners.json.tmp metadata/owners.json

# Then retry
./scripts/manage-metadata.sh add-workflow ...
```

### Problem: Validation Failures

**Symptoms:**
```
✗ Validation FAILED - 3 error(s)
```

**Solution:**
```bash
# Run validation again to see specific errors
./scripts/validate-metadata.sh

# Common issues:
# - Duplicate IDs: Use `grep` to find duplicates
# - Invalid JSON: Use `jq` to check syntax
# - Missing owners: Update owners.json
# - Circular dependencies: Use visualize-dependencies.sh to find them

# After fixing, validate again
./scripts/validate-metadata.sh
```

### Problem: Scripts Not Found

**Symptoms:**
```
./scripts/manage-metadata.sh: No such file or directory
```

**Solution:**
```bash
# Make sure you're in the repo root
pwd  # Should end with "self-hosted-runner"

# Make scripts executable
chmod +x scripts/*-metadata.sh

# Verify
ls -la scripts/*-metadata.sh
```

---

## Getting Help

### Documentation

- [Full Metadata System README](./METADATA_SYSTEM_README.md)
- [Automation Runbook](./AUTOMATION_RUNBOOK.md)

### Commands Help

```bash
# Get help for any command
./scripts/manage-metadata.sh --help
./scripts/validate-metadata.sh --help
./scripts/audit-metadata.sh --help
./scripts/visualize-dependencies.sh --help
```

### Generating Reports

```bash
# Generate comprehensive reports
./scripts/visualize-dependencies.sh

# View the generated report in browser
open dependency-reports/dependencies.html
```

---

**Last Updated:** March 8, 2026  
**Version:** 1.0.0
