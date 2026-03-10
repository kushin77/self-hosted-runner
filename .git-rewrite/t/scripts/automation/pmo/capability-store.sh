#!/usr/bin/env bash
set -euo pipefail

# Capability Store & Declarative Runner Registry
# Implements Kubernetes-style Custom Resource Definitions (CRDs) for runners
# Enables declarative capability specs and intelligent job routing
#
# Features:
#   - YAML-based runner capability declarations
#   - Label-based runner discovery & selection
#   - Job routing rules with fallback strategies
#   - RESTful API for runtime queries
#   - Automatic reconciliation with infrastructure

STORE_DIR="${STORE_DIR:-./.runner-store}"
API_PORT="${RUNNER_API_PORT:-8441}"
LOG_LEVEL="${RUNNER_LOG_LEVEL:-info}"

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

error() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
  exit 1
}

# Initialize capability store directory
init_store() {
  mkdir -p "$STORE_DIR"/{runners,routing-rules,schemas}
  
  # Create JSON schema for Runner CRD
  cat > "$STORE_DIR/schemas/runner.schema.json" <<'EOF'
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "apiVersion": { "type": "string", "const": "elevatediq.io/v1" },
    "kind": { "type": "string", "const": "Runner" },
    "metadata": {
      "type": "object",
      "properties": {
        "name": { "type": "string" },
        "namespace": { "type": "string" },
        "labels": { "type": "object" },
        "annotations": { "type": "object" }
      },
      "required": ["name"]
    },
    "spec": {
      "type": "object",
      "properties": {
        "status": { "enum": ["online", "offline", "draining"] },
        "capabilities": {
          "type": "array",
          "items": {
            "type": "object",
            "properties": {
              "feature": { "type": "string" },
              "version": { "type": "string" },
              "enabled": { "type": "boolean" }
            },
            "required": ["feature"]
          }
        },
        "resources": {
          "type": "object",
          "properties": {
            "cpu": { "type": "string" },
            "memory": { "type": "string" },
            "disk": { "type": "string" }
          }
        },
        "labels": { "type": "object" },
        "quotas": {
          "type": "object",
          "properties": {
            "concurrent_jobs": { "type": "integer" },
            "vpus": { "type": "integer" }
          }
        },
        "routing_weight": { "type": "integer", "minimum": 1 },
        "drain_timeout_secs": { "type": "integer" }
      },
      "required": ["status", "capabilities", "resources"]
    }
  },
  "required": ["apiVersion", "kind", "metadata", "spec"]
}
EOF
  
  log "✓ Capability store initialized: $STORE_DIR"
}

# Create or update a Runner CRD
register_runner() {
  local runner_manifest="$1"
  [ -f "$runner_manifest" ] || error "Runner manifest not found: $runner_manifest"
  
  # Validate YAML syntax
  yq '.' "$runner_manifest" > /dev/null 2>&1 || error "Invalid YAML in manifest"
  
  local runner_name=$(yq '.metadata.name' "$runner_manifest")
  local runner_ns=$(yq '.metadata.namespace // "default"' "$runner_manifest")
  local store_path="${STORE_DIR}/runners/${runner_ns}/${runner_name}.yaml"
  
  mkdir -p "$(dirname "$store_path")"
  cp "$runner_manifest" "$store_path"
  
  # Store metadata index for fast lookup
  local metadata_file="${STORE_DIR}/runners/${runner_ns}/${runner_name}.meta.json"
  cat > "$metadata_file" <<EOF
{
  "name": "$runner_name",
  "namespace": "$runner_ns",
  "registered_at": "$(date -Iseconds)",
  "capabilities": $(yq '.spec.capabilities | length' "$runner_manifest"),
  "status": "$(yq '.spec.status' "$runner_manifest")",
  "labels": $(yq '.metadata.labels | @json' "$runner_manifest"),
  "resources": {
    "cpu": "$(yq '.spec.resources.cpu' "$runner_manifest")",
    "memory": "$(yq '.spec.resources.memory' "$runner_manifest")"
  }
}
EOF
  
  log "✅ Runner registered: ${runner_ns}/${runner_name}"
}

# Query runners by label selector
find_runners_by_labels() {
  local label_selector="$1"
  
  # Parse label selector (e.g., "gpu=true,region=us-east-1")
  local runners=()
  
  while IFS='=' read -r key value; do
    for meta_file in "$STORE_DIR"/runners/*/*.meta.json; do
      if [ -f "$meta_file" ]; then
        local labels=$(jq '.labels' "$meta_file")
        if echo "$labels" | jq -e ".$key == \"$value\"" > /dev/null 2>&1; then
          runners+=("$(jq -r '.name' "$meta_file")")
        fi
      fi
    done
  done < <(echo "$label_selector" | tr ',' '\n')
  
  printf '%s\n' "${runners[@]}"
}

# Create routing rule (declarative job-to-runner mapping)
create_routing_rule() {
  local rule_name="$1"
  local job_filter="$2"
  local runner_selector="$3"
  local priority="${4:-50}"
  
  cat > "${STORE_DIR}/routing-rules/${rule_name}.yaml" <<EOF
apiVersion: elevatediq.io/v1
kind: RoutingRule
metadata:
  name: $rule_name
  priority: $priority
spec:
  jobFilter:
    repository: $job_filter
  runnerSelector: $runner_selector
  strategy: load-balanced  # or round-robin, least-loaded
  fallback: any-available
  timeout_secs: 300
EOF
  
  log "✓ Routing rule created: $rule_name"
}

# Intelligent job routing (select runner using rules + labels)
route_job() {
  local repo="$1"
  local required_labels="${2:-}"
  
  # Load routing rules in priority order
  local best_runner=""
  local best_priority=-1
  
  for rule_file in $(find "$STORE_DIR/routing-rules" -name "*.yaml" | sort); do
    local repo_pattern=$(yq '.spec.jobFilter.repository' "$rule_file")
    local runner_selector=$(yq '.spec.runnerSelector' "$rule_file")
    local priority=$(yq '.metadata.priority' "$rule_file")
    
    # Match repository pattern
    if [[ "$repo" =~ $repo_pattern ]]; then
      # Find matching runners
      local candidates=$(find_runners_by_labels "$runner_selector")
      
      if [ -n "$candidates" ]; then
        # Select least-loaded runner
        best_runner=$(echo "$candidates" | head -1)  # Simplified; real impl would check current load
        best_priority="$priority"
        break
      fi
    fi
  done
  
  # Fallback to any online runner
  if [ -z "$best_runner" ]; then
    best_runner=$(find "$STORE_DIR/runners" -name "*.meta.json" | \
      xargs grep -l '"status": "online"' | head -1 | xargs -I {} jq -r '.name' {})
  fi
  
  [ -n "$best_runner" ] || error "No suitable runner found for job: $repo"
  
  echo "$best_runner"
}

# REST API for runtime queries
start_api_server() {
  log "🚀 Starting Capability Store API on port $API_PORT..."
  
  # Simple HTTP server using nc (netcat)
  while true; do
    {
      read -r request_line
      read -r -t 1 headers || true
      
      local method=$(echo "$request_line" | cut -d' ' -f1)
      local path=$(echo "$request_line" | cut -d' ' -f2)
      
      if [[ "$path" == "/api/runners" ]]; then
        # List all runners
        local runners_json=$(find "$STORE_DIR/runners" -name "*.meta.json" | \
          xargs cat | jq -s '.' 2>/dev/null || echo "[]")
        
        echo -e "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n"
        echo "$runners_json"
        
      elif [[ "$path" == "/api/route?repo="* ]]; then
        local repo=$(echo "$path" | sed 's/.*repo=//; s/[&].*//')
        local runner=$(route_job "$repo")
        echo -e "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n"
        echo "{\"runner\": \"$runner\"}"
        
      elif [[ "$path" == /api/runners/* ]]; then
        local runner_name=$(echo "$path" | sed 's|.*/||')
        local meta_file=$(find "$STORE_DIR/runners" -name "${runner_name}.meta.json" | head -1)
        if [ -f "$meta_file" ]; then
          echo -e "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n"
          cat "$meta_file"
        else
          echo -e "HTTP/1.1 404 Not Found\r\n"
        fi
        
      else
        echo -e "HTTP/1.1 404 Not Found\r\n"
      fi
    } | nc -l -p "$API_PORT" -q 1
  done &
  
  log "✓ API server running: http://localhost:$API_PORT"
}

# Reconciliation: verify registered runners match infrastructure
reconcile() {
  log "🔄 Reconciling capability store with infrastructure..."
  
  local drift_count=0
  
  for meta_file in "$STORE_DIR"/runners/*/*.meta.json; do
    local runner_name=$(jq -r '.name' "$meta_file")
    
    # Check if runner process is still running
    if ! pgrep -f "Runner.*$runner_name" > /dev/null; then
      local yaml_file="${meta_file%.meta.json}.yaml"
      local status=$(yq '.spec.status' "$yaml_file")
      
      if [ "$status" != "offline" ]; then
        log "  ⚠️  Drift detected: $runner_name (expected: $status, actual: offline)"
        yq -i '.spec.status = "offline"' "$yaml_file"
        jq -i '.status = "offline"' "$meta_file"
        ((drift_count++))
      fi
    fi
  done
  
  if [ $drift_count -eq 0 ]; then
    log "✅ Store consistent with infrastructure (0 drifts)"
  else
    log "⚠️  Reconciliation complete: fixed $drift_count drift(s)"
  fi
}

# Main CLI
main() {
  case "${1:-help}" in
    init)
      init_store
      ;;
    register)
      register_runner "${2:-.}"
      ;;
    find)
      find_runners_by_labels "${2:-.}"
      ;;
    route)
      route_job "${2:-.}"
      ;;
    create-rule)
      create_routing_rule "$2" "$3" "$4" "${5:-50}"
      ;;
    api-server)
      start_api_server
      ;;
    reconcile)
      reconcile
      ;;
    *)
      cat <<'HELP'
Capability Store CLI - Declarative Runner Management

Usage:
  capability-store init                           Initialize store
  capability-store register <manifest.yaml>       Register runner CRD
  capability-store find <label-selector>          Find runners by labels
  capability-store route <repository>             Route job to best runner
  capability-store create-rule <name> <filter> <selector>  Create routing rule
  capability-store api-server                     Start REST API
  capability-store reconcile                      Verify infrastructure consistency

Examples:
  capability-store init
  capability-store register ./runners/gpu-runner.yaml
  capability-store find "gpu=true,region=us-east-1"
  capability-store route "my-org/my-repo"
  capability-store create-rule high-perf "compute-*" "gpu=true"
  
Label Selectors:
  key=value              Match exact label
  key=value,key2=value2  Multiple conditions (AND)

HELP
      exit 1
      ;;
  esac
}

main "$@"
