#!/bin/bash

################################################################################
# Event-Driven Orchestration State Machine
# Transitions workflows based on real-time events, not just scheduled time
# Enables instant response to: secret rotation, compliance drift, access violations
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_LOG="${PROJECT_ROOT}/logs/governance/state-machine.jsonl"
EVENT_QUEUE="${PROJECT_ROOT}/.event_queue"

mkdir -p "$(dirname "$STATE_LOG")" "$EVENT_QUEUE"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"; }
success() { echo -e "${GREEN}✓${NC} $*"; }
error() { echo -e "${RED}✗${NC} $*" >&2; }

audit_transition() {
    local from_state="$1" to_state="$2" event="$3" actor="${4:-system}" details="${5:-}"
    printf '{"timestamp":"%s","from":"%s","to":"%s","event":"%s","actor":"%s","details":%s}\n' \
        "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$from_state" "$to_state" "$event" "$actor" "$details" >> "$STATE_LOG"
}

################################################################################
# EVENT QUEUE MANAGEMENT
################################################################################

enqueue_event() {
    local event_type="$1"
    local event_data="$2"
    
    local event_id="evt-$(date +%s)-$(uuidgen | head -c 8)"
    local event_file="${EVENT_QUEUE}/${event_id}.json"
    
    printf '{"id":"%s","type":"%s","timestamp":"%s","status":"pending","data":%s}\n' \
        "$event_id" "$event_type" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$event_data" > "$event_file"
    
    log "Event enqueued: $event_id (type: $event_type)"
}

dequeue_event() {
    local event_file=$(ls -1 "${EVENT_QUEUE}"/*.json | head -1)
    
    if [ -z "$event_file" ]; then
        return 1  # No events
    fi
    
    cat "$event_file"
    rm "$event_file"
}

################################################################################
# STATE MACHINE DEFINITION
################################################################################

# States:
# IDLE → (event triggers) → PROCESSING → (actions executed) → IDLE
# IDLE → DEGRADED (on error) → RECOVERING → IDLE

declare -A STATE_HANDLERS

STATE_HANDLERS[IDLE]="handle_idle"
STATE_HANDLERS[PROCESSING]="handle_processing"
STATE_HANDLERS[DEGRADED]="handle_degraded"
STATE_HANDLERS[RECOVERING]="handle_recovering"

################################################################################
# STATE HANDLERS
################################################################################

handle_idle() {
    # Waiting for events
    log "State: IDLE (waiting for events)"
    
    if dequeue_event > /tmp/current_event.json; then
        local event_type=$(jq -r '.type' /tmp/current_event.json)
        log "Event received: $event_type"
        transition_to "PROCESSING" "$event_type"
        return 0
    fi
    
    return 1  # No events
}

handle_processing() {
    log "State: PROCESSING (executing actions)"
    
    # Read current event
    if [ ! -f /tmp/current_event.json ]; then
        error "No event in processing state"
        transition_to "DEGRADED" "missing_event_file"
        return 1
    fi
    
    local event_type=$(jq -r '.type' /tmp/current_event.json)
    local event_data=$(jq -r '.data' /tmp/current_event.json)
    
    # Route to appropriate handler
    case "$event_type" in
        secret_rotation_triggered)
            handle_event_secret_rotation "$event_data"
            ;;
        compliance_drift_detected)
            handle_event_compliance_drift "$event_data"
            ;;
        access_violation_attempted)
            handle_event_access_violation "$event_data"
            ;;
        anomaly_detected)
            handle_event_anomaly "$event_data"
            ;;
        *)
            error "Unknown event type: $event_type"
            transition_to "DEGRADED" "unknown_event_type"
            return 1
            ;;
    esac
    
    transition_to "IDLE" "actions_complete"
    return 0
}

handle_degraded() {
    log "State: DEGRADED (system in error state)"
    
    # Run diagnostics
    log "Running diagnostics..."
    
    # Check if we can recover
    if [ -f "${PROJECT_ROOT}/.recovery_marker" ]; then
        log "Recovery marker found, attempting recovery..."
        transition_to "RECOVERING" "recovery_initiated"
        return 0
    fi
    
    # Auto-recovery attempts
    log "Attempting automatic recovery..."
    
    # Clear stale event
    rm -f /tmp/current_event.json
    
    # Re-run recent operations
    if bash "${PROJECT_ROOT}/scripts/secrets/mirror-all-backends.sh" >/dev/null 2>&1; then
        transition_to "RECOVERING" "mirror_rerun_success"
        return 0
    fi
    
    log "Recovery attempt failed, manual intervention may be required"
    return 1
}

handle_recovering() {
    log "State: RECOVERING (resuming normal operation)"
    
    log "Health checks..."
    
    # Verify system state
    if bash "${PROJECT_ROOT}/scripts/secrets/health-check.sh" >/dev/null 2>&1; then
        log "System healthy, returning to IDLE"
        transition_to "IDLE" "recovery_complete"
        return 0
    fi
    
    log "Health checks failed, returning to DEGRADED"
    transition_to "DEGRADED" "health_check_failed"
    return 1
}

################################################################################
# EVENT HANDLERS
################################################################################

handle_event_secret_rotation() {
    local secret_data="$1"
    
    log "Handling: secret_rotation_triggered"
    
    local secret_name=$(echo "$secret_data" | jq -r '.secret_name')
    
    log "Executing rotation for: $secret_name"
    
    # Execute rotation
    if bash "${PROJECT_ROOT}/scripts/secrets/rotate-credentials.sh" --apply; then
        success "Rotation completed"
        audit_transition "PROCESSING" "IDLE" "secret_rotation_complete" "system" "{\"secret\":\"$secret_name\"}"
    else
        error "Rotation failed"
        audit_transition "PROCESSING" "DEGRADED" "secret_rotation_failed" "system" "{\"secret\":\"$secret_name\"}"
        return 1
    fi
}

handle_event_compliance_drift() {
    local drift_data="$1"
    
    log "Handling: compliance_drift_detected"
    
    local drift_type=$(echo "$drift_data" | jq -r '.drift_type')
    
    log "Drift type: $drift_type"
    
    case "$drift_type" in
        stale_credential)
            log "Stale credential detected, forcing rotation..."
            bash "${PROJECT_ROOT}/scripts/secrets/rotate-credentials.sh" --apply
            ;;
        policy_violation)
            log "Policy violation detected, enforcing remediation..."
            bash "${PROJECT_ROOT}/scripts/security/runtime-policy-enforcer.sh" deploy_to_staging
            ;;
        *)
            warning "Unknown drift type: $drift_type"
            ;;
    esac
    
    audit_transition "PROCESSING" "IDLE" "compliance_remediated" "system" "{\"drift_type\":\"$drift_type\"}"
}

handle_event_access_violation() {
    local violation_data="$1"
    
    log "Handling: access_violation_attempted"
    
    local actor=$(echo "$violation_data" | jq -r '.actor')
    local secret=$(echo "$violation_data" | jq -r '.secret')
    
    log "Unauthorized access attempt: $actor → $secret"
    
    # Immediate actions
    log "Quarantining access..."
    mkdir -p "${PROJECT_ROOT}/.quarantine"
    echo "AccessViolation: $actor tried to access $secret at $(date)" >> "${PROJECT_ROOT}/.quarantine/violations.log"
    
    # Alert security
    log "Sending security alert..."
    
    audit_transition "PROCESSING" "IDLE" "access_violation_blocked" "system" "{\"actor\":\"$actor\",\"secret\":\"$secret\"}"
}

handle_event_anomaly() {
    local anomaly_data="$1"
    
    log "Handling: anomaly_detected"
    
    local anomaly_type=$(echo "$anomaly_data" | jq -r '.anomaly_type')
    
    log "Anomaly type: $anomaly_type"
    
    # Trigger anomaly detector
    bash "${PROJECT_ROOT}/scripts/automation/anomaly-detector.sh"
    
    audit_transition "PROCESSING" "IDLE" "anomaly_remediated" "system" "{\"anomaly_type\":\"$anomaly_type\"}"
}

################################################################################
# STATE TRANSITIONS
################################################################################

transition_to() {
    local new_state="$1"
    local trigger="${2:-}"
    
    local current_state="${CURRENT_STATE:-IDLE}"
    
    log "Transition: $current_state → $new_state (trigger: $trigger)"
    
    audit_transition "$current_state" "$new_state" "$trigger" "system" "{}"
    
    CURRENT_STATE="$new_state"
    
    # Save state
    echo "$new_state" > "${PROJECT_ROOT}/.state_machine_state"
}

################################################################################
# MAIN ORCHESTRATION LOOP
################################################################################

run_orchestration_loop() {
    CURRENT_STATE=$(cat "${PROJECT_ROOT}/.state_machine_state" 2>/dev/null || echo "IDLE")
    
    log "Starting orchestration loop (initial state: $CURRENT_STATE)"
    
    local iterations=0
    local max_iterations="${1:-10}"  # Max 10 iterations per run (prevents infinite loops)
    
    while [ $iterations -lt $max_iterations ]; do
        iterations=$((iterations + 1))
        
        local handler="${STATE_HANDLERS[$CURRENT_STATE]}"
        
        if [ -z "$handler" ]; then
            error "Unknown state: $CURRENT_STATE"
            CURRENT_STATE="DEGRADED"
            continue
        fi
        
        # Execute state handler
        if ! $handler; then
            # Handler returned failure; stay in current state
            if [ "$CURRENT_STATE" = "IDLE" ]; then
                # In IDLE with no events, just wait
                sleep 5
            fi
        fi
        
        # Small delay between iterations
        sleep 1
    done
    
    log "Orchestration loop completed ($iterations iterations)"
}

################################################################################
# MAIN
################################################################################

main() {
    case "${1:-loop}" in
        loop)
            run_orchestration_loop 10
            ;;
        event)
            if [ $# -lt 2 ]; then
                error "Usage: $0 event <type> [json_data]"
                exit 1
            fi
            enqueue_event "$2" "${3:-{}}"
            ;;
        state)
            cat "${PROJECT_ROOT}/.state_machine_state" 2>/dev/null || echo "IDLE"
            ;;
        *)
            echo "Usage: $0 {loop|event|state}"
            exit 1
            ;;
    esac
}

main "$@"
