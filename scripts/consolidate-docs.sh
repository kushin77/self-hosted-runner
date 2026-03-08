#!/usr/bin/env bash
# Consolidate documentation files into organized structure
# This script categorizes 240+ markdown files into:
# - docs/runbooks/  (operational, living docs)
# - docs/architecture/ (design documentation)
# - docs/decisions/ (ADRs)
# - docs/archive/ (historical phase completion reports)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCS_DIR="${REPO_ROOT}/docs"

# Categories for files (regex patterns for matching)
declare -A RUNBOOK_PATTERNS=(
  ["AUTOMATION_RUNBOOK"]="1"
  ["RUNBOOK"]="1"
  ["GUIDE"]="1"
  ["OPERATIONS"]="1"
  ["HANDS_OFF"]="1"
  ["QUICKSTART"]="1"
  ["GETTING_STARTED"]="1"
  ["HOW_TO"]="1"
  ["CHECKLIST"]="1"
)

declare -A ARCHITECTURE_PATTERNS=(
  ["ARCHITECTURE"]="1"
  ["DESIGN"]="1"
  ["INFRASTRUCTURE"]="1"
  ["SYSTEMS"]="1"
  ["INTEGRATION"]="1"
  ["MULTI_CLOUD"]="1"
  ["SECURITY_MODEL"]="1"
  ["OIDC"]="1"
  ["WORKLOAD_IDENTITY"]="1"
)

declare -A ARCHIVE_PATTERNS=(
  ["COMPLETE"]="1"
  ["SUMMARY"]="1"
  ["FINAL"]="1"
  ["STATUS"]="1"
  ["REPORT"]="1"
  ["PHASE"]="1"
  ["DEPLOYMENT_FINAL"]="1"
  ["EXECUTION"]="1"
  ["ACTIVATION"]="1"
)

# Files to keep at root
declare -A ROOT_FILES=(
  ["README"]="1"
  ["CONTRIBUTING"]="1"
  ["CHANGELOG"]="1"
  ["LICENSE"]="1"
)

categorize_file() {
  local file="$1"
  local base="${file%.md}"
  
  # Check if should stay at root
  for pattern in "${!ROOT_FILES[@]}"; do
    if [[ "$base" =~ $pattern ]]; then
      echo "root"
      return
    fi
  done
  
  # Check archive patterns first (most specific)
  for pattern in "${!ARCHIVE_PATTERNS[@]}"; do
    if [[ "$base" =~ $pattern ]]; then
      echo "archive"
      return
    fi
  done
  
  # Check architecture patterns
  for pattern in "${!ARCHITECTURE_PATTERNS[@]}"; do
    if [[ "$base" =~ $pattern ]]; then
      echo "architecture"
      return
    fi
  done
  
  # Check runbook patterns
  for pattern in "${!RUNBOOK_PATTERNS[@]}"; do
    if [[ "$base" =~ $pattern ]]; then
      echo "runbooks"
      return
    fi
  done
  
  # Default to archive if uncertain
  echo "archive"
}

main() {
  echo "📚 Documentation Consolidation Script"
  echo "====================================="
  
  # Create directory structure if not exists
  mkdir -p "${DOCS_DIR}/runbooks"
  mkdir -p "${DOCS_DIR}/architecture"
  mkdir -p "${DOCS_DIR}/decisions"
  mkdir -p "${DOCS_DIR}/archive"
  
  local -A stats
  stats[root]=0
  stats[runbooks]=0
  stats[architecture]=0
  stats[decisions]=0
  stats[archive]=0
  
  # Process all .md files in repo root
  echo "📋 Categorizing files..."
  for file in "${REPO_ROOT}"/*.md; do
    [ -f "$file" ] || continue
    
    filename=$(basename "$file")
    category=$(categorize_file "$filename")
    
    if [[ "$category" == "root" ]]; then
      ((stats[root]++))
      echo "  ✓ Keep @root: $filename"
    else
      target_dir="${DOCS_DIR}/${category}"
      echo "  → Move to $category: $filename"
      
      # Don't actually move, just report for now (add --move flag to apply)
      ((stats[$category]++))
    fi
  done
  
  echo ""
  echo "📊 Summary (--dry-run mode):"
  echo "  Root files to keep: ${stats[root]}"
  echo "  Files → docs/runbooks: ${stats[runbooks]}"
  echo "  Files → docs/architecture: ${stats[architecture]}"
  echo "  Files → docs/decisions: ${stats[decisions]}"
  echo "  Files → docs/archive: ${stats[archive]}"
  echo ""
  echo "💡 Run with --apply flag to move files:"
  echo "   $0 --apply"
}

main "$@"
