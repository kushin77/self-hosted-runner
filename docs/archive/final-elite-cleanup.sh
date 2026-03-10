#!/bin/bash
set -e

echo "🧹 FINAL ELITE CLEANUP..."

# Move remaining blocker/complex analysis files to archive
find . -maxdepth 1 -type f \( \
  -name "*BLOCKER*.md" \
  -o -name "*BLOCKED*.md" \
  -o -name "*UNBLOCK*.md" \
  -o -name "*ANALYSIS*.md" \
  -o -name "OAUTH*.md" \
  -o -name "GCP*.md" \
  -o -name "TERRAFORM_*.md" \
  -o -name "VAULT*.md" \
  -o -name "GITHUB_GOVERNANCE*.md" \
  -o -name "ORG_*.md" \
  -o -name "*COMPLIANCE*.md" \
  -o -name "*ADMIN*.md" \
  -o -name "FAANG*.md" \
  -o -name "QUARTERLY*.md" \
  -o -name "*RCA*.md" \
  -o -name "MIGRATE*.md" \
  \) -exec mv {} docs/archive/ \;

# Move setup/provisioning guides
find . -maxdepth 1 -type f \( \
  -name "*PROVISIONING*.md" \
  -o -name "FULLSTACK*.md" \
  \) -exec mv {} docs/deployment/ \;

# Move log files to logs/
find . -maxdepth 1 -type f \( -name "*.log" -o -name "*.txt" \) ! -name ".env*" -exec mv {} logs/ \;

# Keep only essential in root
echo ✅ "Moved remaining files to appropriate directories"

# Show final root status
echo ""
echo "=== FINAL ROOT DIRECTORY STATUS ==="
ls -la | grep -E "^-" | grep -v "^\." | wc -l
echo "files remaining"
echo ""

