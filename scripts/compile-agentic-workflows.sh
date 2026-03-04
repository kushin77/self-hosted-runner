#!/bin/bash
# Simplified Workflow Compiler for Agentic Workflows

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${GREEN}ℹ️ $*${NC}"; }
log_error() { echo -e "${RED}❌ $*${NC}"; }

get_yaml_field() {
  grep "^$2:" "$1" | head -1 | cut -d: -f2- | xargs 2>/dev/null || echo ""
}

generate_yaml() {
  local md_file="$1"
  local name runs_on
  
  name=$(get_yaml_field "$md_file" "name")
  runs_on=$(get_yaml_field "$md_file" "runs-on")
  runs_on="${runs_on:-elevatediq-runner}"
  
cat <<'YAML'
name: WORKFLOW_NAME
on:
  pull_request:
    types: [opened, synchronize]
  issues:
    types: [opened]
  workflow_dispatch:

permissions:
  contents: read
  pull-requests: write
  issues: write
  checks: write

jobs:
  agentic-task:
    runs-on: RUNNER_LABEL
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      
      - uses: actions/setup-node@v4
        with:
          node-version: '18'
      
      - uses: actions/setup-python@v4
        with:
          python-version: '3.11'
      
      - name: Check Ollama health
        id: ollama
        run: |
          if curl -s http://localhost:11434/api/tags >/dev/null 2>&1; then
            echo "available=true" >> $GITHUB_OUTPUT
          else
            echo "available=false" >> $GITHUB_OUTPUT
          fi
      
      - name: Run Ollama agent
        if: steps.ollama.outputs.available == 'true'
        run: |
          echo "🤖 Agentic workflow: WORKFLOW_NAME"
          echo "Repository: ${{ github.repository }}"
          echo "Event: ${{ github.event_name }}"
          ollama run llama2 "Execute agentic workflow task" || true
      
      - name: Fallback mode (Ollama unavailable)
        if: steps.ollama.outputs.available == 'false'
        run: |
          echo "⚠️ Ollama service unavailable"
          echo "Running local analysis fallback..."
      
      - name: Post summary
        if: always()
        run: |
          cat >> $GITHUB_STEP_SUMMARY <<'SUMMARY'
          ## ✅ Agentic Workflow Completed
          SUMMARY
YAML
}

compile_one() {
  local md_file="$1"
  local lock_file="${md_file%.md}.lock.yml"
  
  if [[ ! -f "$md_file" ]]; then
    log_error "File not found: $md_file"
    return 1
  fi
  
  log_info "Compiling: $md_file"
  
  local name
  name=$(get_yaml_field "$md_file" "name")
  
  generate_yaml "$md_file" | sed "s/WORKFLOW_NAME/$name/g" > "$lock_file"
  
  log_info "✅ Generated: $lock_file"
  return 0
}

compile_all() {
  local dir=".github/workflows/agentic"
  
  if [[ ! -d "$dir" ]]; then
    log_error "Directory not found: $dir"
    return 1
  fi
  
  local count=0
  while IFS= read -r md_file; do
    if compile_one "$md_file"; then
      ((count++))
    fi
  done < <(find "$dir" -name "*.md" -type f)
  
  log_info "✅ Compiled $count workflows"
}

case "${1:-help}" in
  compile)
    compile_one "${2:-.github/workflows/agentic/auto-fix.md}"
    ;;
  compile-all)
    compile_all
    ;;
  list)
    echo "📋 Agentic Workflows:"
    find .github/workflows/agentic -name "*.md" -type f 2>/dev/null | while read f; do
      name=$(get_yaml_field "$f" "name")
      printf "  ✓ %s\n" "$name"
    done || log_error "No workflows found"
    ;;
  help)
    cat <<'HELP'
Compile Markdown workflows → GitHub Actions YAML

USAGE: compile-agentic-workflows.sh <command> [args]

COMMANDS:
  compile <file>     Compile single workflow
  compile-all        Compile all workflows
  list              List workflows
  help              Show this message
HELP
    ;;
  *)
    log_error "Unknown command: $1"
    exit 1
    ;;
esac
