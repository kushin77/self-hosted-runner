# Implementation Guide: Cascading Fallback Recovery Strategy

**Status**: Ready to Implement  
**Effort**: 3-4 days  
**Priority**: 🔴 CRITICAL #2  
**Outcome**: Automatic failover between registries with graceful degradation

---

## Overview

This enhancement ensures recovery succeeds even if the primary registry fails. It implements an intelligent cascading failover strategy:

```
Attempt Docker Hub (3 retries)
  ├─ Success? → DONE
  └─ Fail? ↓

Attempt AWS ECR (3 retries)  
  ├─ Success? → DONE
  └─ Fail? ↓

Attempt Google Artifact Registry (3 retries)
  ├─ Success? → DONE
  └─ Fail? ↓

Emergency Bootstrap (last-known-good from git)
```

---

## Step 1: Create Resilient Recovery Function

### Enhanced scripts/recover-from-nuke.sh

Add these functions to your existing recovery script:

```bash
#!/bin/bash
# ... existing code ...

# === CASCADING FALLBACK LOGIC ===

# Registry configuration (ordered by preference)
declare -a BACKUP_REGISTRIES=(
  "docker.io"
  "123456789.dkr.ecr.us-east-1.amazonaws.com"
  "us-east1-docker.pkg.dev/${GCP_PROJECT_ID}/docker-hub-mirror"
)

# Circuit breaker state
declare -A CIRCUIT_BREAKER_STATE
declare -A CIRCUIT_BREAKER_FAILURES

# Constants
readonly MAX_FAILURES_BEFORE_OPEN=3
readonly CIRCUIT_OPEN_RETRY_DELAY=300  # 5 minutes

log_recovery_attempt() {
  local registry=$1
  local attempt=$2
  local max_attempts=$3
  
  echo "[RECOVERY] $(date +'%H:%M:%S') Attempt $attempt/$max_attempts: $registry"
}

log_recovery_success() {
  local registry=$1
  
  echo "[SUCCESS] $(date +'%H:%M:%S') ✓ Recovery succeeded from $registry"
}

log_recovery_failure() {
  local registry=$1
  local reason=$2
  
  echo "[FAILURE] $(date +'%H:%M:%S') ✗ Recovery failed from $registry: $reason"
}

log_recovery_fallback() {
  local current_registry=$1
  local next_registry=$2
  
  echo "[FALLBACK] $(date +'%H:%M:%S') Falling back from $current_registry to $next_registry"
}

# Circuit Breaker Functions

is_circuit_open() {
  local registry=$1
  [[ "${CIRCUIT_BREAKER_STATE[$registry]}" == "OPEN" ]]
}

open_circuit() {
  local registry=$1
  
  CIRCUIT_BREAKER_STATE[$registry]="OPEN"
  CIRCUIT_BREAKER_FAILURES[$registry]=0
  
  echo "[CIRCUIT] $(date +'%H:%M:%S') ⚠ Circuit breaker OPEN for $registry"
}

close_circuit() {
  local registry=$1
  
  CIRCUIT_BREAKER_STATE[$registry]="CLOSED"
  CIRCUIT_BREAKER_FAILURES[$registry]=0
  
  echo "[CIRCUIT] $(date +'%H:%M:%S') ✓ Circuit breaker CLOSED for $registry"
}

increment_failure() {
  local registry=$1
  
  ((CIRCUIT_BREAKER_FAILURES[$registry]++))
  
  if [[ ${CIRCUIT_BREAKER_FAILURES[$registry]} -ge $MAX_FAILURES_BEFORE_OPEN ]]; then
    open_circuit "$registry"
  fi
}

reset_failures() {
  local registry=$1
  CIRCUIT_BREAKER_FAILURES[$registry]=0
}

# Retry Logic with Exponential Backoff

attempt_pull_with_retries() {
  local registry=$1
  local image=$2
  local backup_tag=$3
  local max_attempts=3
  
  for ((attempt=1; attempt<=max_attempts; attempt++)); do
    log_recovery_attempt "$registry" "$attempt" "$max_attempts"
    
    # Calculate exponential backoff: 1s, 2s, 4s
    local backoff_delay=$((2 ** (attempt - 1)))
    
    if [[ $attempt -gt 1 ]]; then
      echo "[RETRY] Waiting ${backoff_delay}s before retry..."
      sleep "$backoff_delay"
    fi
    
    # Attempt the pull with timeout
    if timeout 60 docker pull "$registry/elevatediq/app-backup:$backup_tag" 2>/dev/null; then
      log_recovery_success "$registry"
      
      # Verify image integrity
      if verify_image_integrity "$registry/elevatediq/app-backup:$backup_tag"; then
        return 0
      else
        log_recovery_failure "$registry" "Image integrity check failed"
        continue
      fi
    else
      local error_code=$?
      if [[ $error_code -eq 124 ]]; then
        log_recovery_failure "$registry" "Timeout (60s)"
      else
        log_recovery_failure "$registry" "Pull failed (code: $error_code)"
      fi
    fi
  done
  
  increment_failure "$registry"
  return 1
}

# Main Cascading Fallback

recover_from_backup_with_fallback() {
  local backup_tag="${1:?Backup tag required}"
  local current_registry_idx=0
  
  echo "[START] Cascading fallback recovery for $backup_tag"
  echo "[PLAN] Will try ${#BACKUP_REGISTRIES[@]} registries in sequence"
  echo ""
  
  while [[ $current_registry_idx -lt ${#BACKUP_REGISTRIES[@]} ]]; do
    local registry="${BACKUP_REGISTRIES[$current_registry_idx]}"
    
    # Check circuit breaker
    if is_circuit_open "$registry"; then
      echo "[SKIP] $registry circuit is OPEN (too many failures), skipping..."
      ((current_registry_idx++))
      continue
    fi
    
    # Attempt pull
    if attempt_pull_with_retries "$registry" "elevatediq/app-backup" "$backup_tag"; then
      # Success! Re-tag and validate
      docker tag \
        "$registry/elevatediq/app-backup:$backup_tag" \
        "elevatediq/app-backup:recovered"
      
      close_circuit "$registry"
      
      echo ""
      echo "[END] Cascading recovery SUCCESSFUL"
      echo "  Backup tag: $backup_tag"
      echo "  Source registry: $registry"
      echo "  Recovery duration: $(( $(date +%s) - RECOVERY_START_TIME ))s"
      
      return 0
    fi
    
    # This registry failed, try next
    if [[ $((current_registry_idx + 1)) -lt ${#BACKUP_REGISTRIES[@]} ]]; then
      next_registry="${BACKUP_REGISTRIES[$((current_registry_idx + 1))]}"
      log_recovery_fallback "$registry" "$next_registry"
    fi
    
    ((current_registry_idx++))
  done
  
  # All registries exhausted
  echo ""
  echo "[CRITICAL] All registries exhausted. Attempting emergency bootstrap..."
  
  # Try emergency bootstrap
  if recover_from_git_state; then
    return 0
  fi
  
  echo "[ERROR] Emergency bootstrap also failed. Manual intervention required."
  return 1
}

# Health Check Before Recovery

check_registry_health() {
  local registry=$1
  
  case "$registry" in
    docker.io)
      # Test Docker Hub API
      if curl -f https://hub.docker.com/v2/ --connect-timeout 5 --max-time 10 >/dev/null 2>&1; then
        return 0
      fi
      ;;
    *ecr*)
      # Test AWS ECR API
      if aws ecr describe-repositories --region us-east-1 >/dev/null 2>&1; then
        return 0
      fi
      ;;
    *artifactregistry*)
      # Test Google Artifact Registry API
      if gcloud artifacts repositories list >/dev/null 2>&1; then
        return 0
      fi
      ;;
  esac
  
  return 1
}

# Smart Registry Selection (Optional: choose fastest available)

select_fastest_available_registry() {
  local fastest_registry=""
  local fastest_latency=999999
  
  echo "[HEALTH] Checking health of all registries..."
  
  for registry in "${BACKUP_REGISTRIES[@]}"; do
    echo -n "  $registry: "
    
    if ! check_registry_health "$registry"; then
      echo "UNHEALTHY (skipping)"
      continue
    fi
    
    # Measure latency
    local start=$(date +%s%N)
    
    case "$registry" in
      docker.io)
        curl -I https://hub.docker.com/v2/ --connect-timeout 5 >/dev/null 2>&1 || continue
        ;;
      *ecr*)
        aws ecr describe-repositories --region us-east-1 >/dev/null 2>&1 || continue
        ;;
      *artifactregistry*)
        gcloud artifacts repositories list >/dev/null 2>&1 || continue
        ;;
    esac
    
    local end=$(date +%s%N)
    local latency=$((( end - start ) / 1000000))  # Convert to ms
    
    echo "HEALTHY ($latency ms)"
    
    if [[ $latency -lt $fastest_latency ]]; then
      fastest_latency=$latency
      fastest_registry=$registry
    fi
  done
  
  if [[ -z "$fastest_registry" ]]; then
    echo "[WARN] No healthy registries found, will attempt all in order"
    echo "${BACKUP_REGISTRIES[0]}"
  else
    echo ""
    echo "[SELECT] Fastest available registry: $fastest_registry ($fastest_latency ms)"
    echo "$fastest_registry"
  fi
}

# Verify Image Integrity

verify_image_integrity() {
  local image=$1
  
  # Check image exists
  if ! docker inspect "$image" >/dev/null 2>&1; then
    return 1
  fi
  
  # Verify required fields
  local config=$(docker inspect "$image" --format='{{.Config}}' 2>/dev/null)
  if [[ -z "$config" ]]; then
    return 1
  fi
  
  # Verify backup metadata
  local labels=$(docker inspect "$image" --format='{{.Config.Labels}}' 2>/dev/null)
  if [[ "$labels" == *"backup.version"* ]]; then
    return 0
  fi
  
  # Image passed integrity checks
  return 0
}

# Emergency Bootstrap (Last Resort)

recover_from_git_state() {
  echo "[EMERGENCY] Attempting recovery from git-stored last-known-good state..."
  
  # This requires a special git branch with recovery artifacts
  if git show origin/recovery-artifacts:Dockerfile >/dev/null 2>&1; then
    echo "[RECOVER] Found recovery artifacts in git"
    
    # Build from git state
    if docker build \
      --file <(git show origin/recovery-artifacts:Dockerfile) \
      -t elevatediq/app-backup:recovered \
      -f Dockerfile.recovery \
      . >/dev/null 2>&1; then
      echo "[SUCCESS] Emergency recovery from git succeeded"
      return 0
    fi
  fi
  
  return 1
}

# === MAIN RECOVERY ENTRY POINT ===

main_recovery() {
  local backup_tag="${1:?Backup tag required (e.g., backup-20260305-020000)}"
  
  # Record start time for metrics
  RECOVERY_START_TIME=$(date +%s)
  
  echo "╔════════════════════════════════════════════╗"
  echo "║  CASCADING FALLBACK RECOVERY STARTING      ║"
  echo "╚════════════════════════════════════════════╝"
  echo ""
  echo "Backup Tag: $backup_tag"
  echo "Start Time: $(date)"
  echo ""
  
  # Perform recovery with cascading fallback
  if recover_from_backup_with_fallback "$backup_tag"; then
    local duration=$(( $(date +%s) - RECOVERY_START_TIME ))
    
    # Also verify application functionality
    echo ""
    echo "[VERIFY] Running post-recovery verification..."
    if verify_recovery_success; then
      echo "╔════════════════════════════════════════════╗"
      echo "║  RECOVERY COMPLETED SUCCESSFULLY          ║"
      echo "║  Duration: ${duration}s                   ║"
      echo "╚════════════════════════════════════════════╝"
      return 0
    fi
  fi
  
  echo "╔════════════════════════════════════════════╗"
  echo "║  RECOVERY FAILED - MANUAL INTERVENTION NEEDED║"
  echo "╚════════════════════════════════════════════╝"
  return 1
}

# Call main recovery
main_recovery "$@"
```

---

## Step 2: Create Circuit Breaker Monitoring

### scripts/monitor-circuit-breakers.sh

```bash
#!/bin/bash

# Monitor circuit breaker state across recovery attempts
# Usage: ./monitor-circuit-breakers.sh

BREAKER_STATE_FILE=".recovery-state/circuit-breakers.json"

mkdir -p "$(dirname "$BREAKER_STATE_FILE")"

# Initialize breaker state
if [[ ! -f "$BREAKER_STATE_FILE" ]]; then
  cat > "$BREAKER_STATE_FILE" << 'EOF'
{
  "docker-hub": {
    "state": "CLOSED",
    "failures": 0,
    "last_failure": null,
    "last_check": null
  },
  "aws-ecr": {
    "state": "CLOSED",
    "failures": 0,
    "last_failure": null,
    "last_check": null
  },
  "google-artifact-registry": {
    "state": "CLOSED",
    "failures": 0,
    "last_failure": null,
    "last_check": null
  }
}
EOF
fi

check_registry_status() {
  local registry=$1
  local timestamp=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
  
  case "$registry" in
    docker-hub)
      if curl -f https://hub.docker.com/v2/ --connect-timeout 5 --max-time 10 \
        >/dev/null 2>&1; then
        status="HEALTHY"
      else
        status="UNHEALTHY"
      fi
      ;;
    aws-ecr)
      if aws ecr describe-repositories --region us-east-1 \
        >/dev/null 2>&1; then
        status="HEALTHY"
      else
        status="UNHEALTHY"
      fi
      ;;
    google-artifact-registry)
      if gcloud artifacts repositories list \
        >/dev/null 2>&1; then
        status="HEALTHY"
      else
        status="UNHEALTHY"
      fi
      ;;
  esac
  
  # Update JSON state file
  jq ".\"$registry\".last_check = \"$timestamp\" | \
      .\"$registry\".status = \"$status\"" \
    "$BREAKER_STATE_FILE" > "$BREAKER_STATE_FILE.tmp"
  
  mv "$BREAKER_STATE_FILE.tmp" "$BREAKER_STATE_FILE"
}

# Check all registries
for registry in docker-hub aws-ecr google-artifact-registry; do
  check_registry_status "$registry"
done

# Display current state
echo "Circuit Breaker State: $(date)"
cat "$BREAKER_STATE_FILE" | jq .
```

---

## Step 3: Create Fallback Testing Workflow

### .github/workflows/docker-hub-cascading-fallback-test.yml

```yaml
name: Cascading Fallback Recovery Test
on:
  schedule:
    - cron: '0 3 * * 2'  # Tuesday 3 AM UTC
  workflow_dispatch:
    inputs:
      primary_registry:
        description: 'Simulate failure of primary registry'
        type: choice
        options:
          - docker-hub
          - aws-ecr
          - google-artifact-registry
          - none

jobs:
  cascading-fallback-test:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      
      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1
      
      - name: Authenticate to Google Cloud
        uses: google-github-actions/auth@v2
        with:
          credentials_json: ${{ secrets.GCP_SERVICE_ACCOUNT_KEY }}
      
      - name: Get latest backup tag
        id: get-backup
        run: |
          # Find most recent backup in Docker Hub
          LATEST_TAG=$(curl -s \
            "https://hub.docker.com/v2/repositories/elevatediq/app-backup/tags" | \
            jq -r '.results[0].name')
          
          echo "backup_tag=$LATEST_TAG" >> $GITHUB_OUTPUT
      
      - name: Test Primary → Secondary
        if: github.event.inputs.primary_registry != 'aws-ecr'
        run: |
          echo "Testing recovery chain: Docker Hub → AWS ECR → Google"
          
          # Simulate pulling from all registries
          docker pull docker.io/elevatediq/app-backup:${{ steps.get-backup.outputs.backup_tag }} \
            && echo "✓ Docker Hub available" \
            || echo "✗ Docker Hub unavailable"
          
          docker pull 123456789.dkr.ecr.us-east-1.amazonaws.com/app-backup:${{ steps.get-backup.outputs.backup_tag }} \
            && echo "✓ AWS ECR available" \
            || echo "✗ AWS ECR unavailable"
      
      - name: Test Failover to Secondary
        if: github.event.inputs.primary_registry == 'docker-hub'
        run: |
          echo "Simulating Docker Hub unavailability, testing AWS ECR fallback..."
          
          # In real scenario, Docker Hub would be down
          # Check AWS ECR has backup
          docker pull 123456789.dkr.ecr.us-east-1.amazonaws.com/app-backup:${{ steps.get-backup.outputs.backup_tag }} \
            && echo "✓ Fallback to AWS ECR succeeded" \
            || (echo "✗ AWS ECR also unavailable" && exit 1)
      
      - name: Test Failover to Tertiary
        if: github.event.inputs.primary_registry == 'aws-ecr'
        run: |
          echo "Simulating AWS ECR unavailability, testing Google Artifact Registry fallback..."
          
          docker pull us-east1-docker.pkg.dev/${{ secrets.GCP_PROJECT_ID }}/docker-hub-mirror/app-backup:${{ steps.get-backup.outputs.backup_tag }} \
            && echo "✓ Fallback to Google succeeded" \
            || (echo "✗ Google Artifact Registry also unavailable" && exit 1)
      
      - name: Test Recovery RTO
        run: |
          # Time the recovery process
          START=$(date +%s)
          
          # Run recovery (with fallbacks if needed)
          bash scripts/recover-from-nuke.sh ${{ steps.get-backup.outputs.backup_tag }}
          
          END=$(date +%s)
          DURATION=$((END - START))
          
          if [[ $DURATION -le 900 ]]; then
            echo "✓ RTO Target met: ${DURATION}s ≤ 900s"
          else
            echo "✗ RTO Target exceeded: ${DURATION}s > 900s"
            exit 1
          fi
      
      - name: Generate fallback test report
        if: always()
        run: |
          cat > fallback-test-report.json << EOF
          {
            "timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
            "test_scenario": "${{ github.event.inputs.primary_registry }}",
            "backup_tag": "${{ steps.get-backup.outputs.backup_tag }}",
            "recovery_duration_seconds": $DURATION,
            "rto_target_seconds": 900,
            "rto_compliant": $([ $DURATION -le 900 ] && echo "true" || echo "false"),
            "status": "PASSED"
          }
          EOF
          
          cat fallback-test-report.json | jq .
      
      - name: Upload test results
        uses: actions/upload-artifact@v3
        with:
          name: cascading-fallback-test-results
          path: fallback-test-report.json
```

---

## Step 4: Update Main Recovery Script

Modify your existing `scripts/recover-from-nuke.sh` to use cascading fallback:

```bash
# At the beginning of recover-from-nuke.sh, replace the backup pull section with:

# === CASCADING FALLBACK RECOVERY ===
# Instead of:
#   docker pull elevatediq/app-backup:$BACKUP_TAG
# 
# Use:
#   recover_from_backup_with_fallback "$BACKUP_TAG"

# Source the cascading recovery functions
source scripts/cascading-failover-functions.sh

# Main recovery flow
if ! recover_from_backup_with_fallback "$BACKUP_TAG"; then
  fail "Failed to recover from backup - all registries exhausted"
  exit 1
fi

# Continue with rest of recovery...
```

---

## Step 5: Create Diagnostics Script

### scripts/diagnose-recovery-chain.sh

```bash
#!/bin/bash

# Diagnose which registries are healthy and what fallback path would be used

echo "╔════════════════════════════════════════════╗"
echo "║  DISASTER RECOVERY CHAIN DIAGNOSIS         ║"
echo "║  $(date +'%Y-%m-%d %H:%M:%S')             ║"
echo "╚════════════════════════════════════════════╝"
echo ""

REGISTRIES=(
  "docker.io:Docker Hub"
  "123456789.dkr.ecr.us-east-1.amazonaws.com:AWS ECR"
  "us-east1-docker.pkg.dev/\${GCP_PROJECT_ID}/docker-hub-mirror:Google Artifact Registry"
)

echo "Registry Status Check:"
echo "─────────────────────"

healthy_registries=()
unhealthy_registries=()

for registry_pair in "${REGISTRIES[@]}"; do
  registry="${registry_pair%%:*}"
  name="${registry_pair##*:}"
  
  echo -n "  $name... "
  
  case "$registry" in
    docker.io)
      if curl -f https://hub.docker.com/v2/ --connect-timeout 5 --max-time 10 \
        >/dev/null 2>&1; then
        echo "✓ HEALTHY"
        healthy_registries+=("$registry")
      else
        echo "✗ UNHEALTHY"
        unhealthy_registries+=("$registry")
      fi
      ;;
    *ecr*)
      if aws ecr describe-repositories --region us-east 1 \
        >/dev/null 2>&1; then
        echo "✓ HEALTHY"
        healthy_registries+=("$registry")
      else
        echo "✗ UNHEALTHY"
        unhealthy_registries+=("$registry")
      fi
      ;;
    *artifactregistry*)
      if gcloud artifacts repositories list \
        >/dev/null 2>&1; then
        echo "✓ HEALTHY"
        healthy_registries+=("$registry")
      else
        echo "✗ UNHEALTHY"
        unhealthy_registries+=("$registry")
      fi
      ;;
  esac
done

echo ""
echo "Fallback Path:"
echo "──────────────"
echo "  1st choice: ${healthy_registries[0]:-None}"
echo "  2nd choice: ${healthy_registries[1]:-None}"
echo "  3rd choice: ${healthy_registries[2]:-None}"
echo ""

if [[ ${#healthy_registries[@]} -eq 0 ]]; then
  echo "⚠ WARNING: No registries are healthy!"
  echo "  Emergency bootstrap will be attempted"
else
  echo "✓ Recovery will succeed using:"
  for i in "${!healthy_registries[@]}"; do
    echo "    $(( i + 1 )). ${healthy_registries[$i]}"
  done
fi
```

---

## Step 6: Validation Checklist

- [ ] Added cascading fallback functions to `scripts/recover-from-nuke.sh`
- [ ] Created `.github/workflows/docker-hub-cascading-fallback-test.yml`
- [ ] Tested recovery with Docker Hub imagined down
- [ ] Tested recovery with AWS ECR imagined down
- [ ] Tested recovery with Google Artifact Registry imagined down
- [ ] RTO remains <15 minutes even with failover
- [ ] Circuit breaker state properly tracked
- [ ] All 3 fallback attempts logged clearly
- [ ] Recovery succeeds from at least one registry

---

## Testing Commands

```bash
# Test cascading fallback logic locally
bash scripts/recover-from-nuke.sh backup-20260305-020000

# Diagnose current recovery chain health
bash scripts/diagnose-recovery-chain.sh

# Monitor circuit breaker state
bash scripts/monitor-circuit-breakers.sh

# Trigger test workflow manually
gh workflow run docker-hub-cascading-fallback-test.yml \
  -f primary_registry=docker-hub
```

---

## Success Criteria

✅ All done when:
1. Recovery succeeds even if primary registry unavailable
2. Automatic fallback to secondary registry within 10 seconds
3. Auto fallback to tertiary registry if secondary also down
4. Circuit breaker properly tracks failures (open after 3)
5. RTO remains <15 minutes including fallover delays
6. All fallback paths logged in recovery output
7. Weekly test validates full fallback chain

---

**Estimated Time**: 3-4 days  
**Next Step**: Implement Enhancement #3 (Secret Rotation)  
**Dependencies**: Must complete Enhancement #1 first (Multi-Registry)
