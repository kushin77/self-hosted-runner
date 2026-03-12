#!/bin/bash

################################################################################
# Idle Resource Cleanup - 5 Minute Enforcement
# Shutdown all cloud resources after 5 min inactivity in development
# Zero-cost during idle periods | Auto-trigger on demand
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOGS_DIR="${PROJECT_ROOT}/logs/cost-management"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
IDLE_THRESHOLD_MINS=5
IDLE_THRESHOLD_SECS=$((IDLE_THRESHOLD_MINS * 60))

# Safety: destructive cleanup is disabled by default.
# Require explicit opt-in via ENABLE_IDLE_CLEANUP=true (or FORCE_CLEANUP=true).
if [[ "${ENABLE_IDLE_CLEANUP:-}" != "true" && "${FORCE_CLEANUP:-}" != "true" ]]; then
    log "Idle resource cleanup is disabled by default. To enable set ENABLE_IDLE_CLEANUP=true or pass FORCE_CLEANUP=true"
    exit 0
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

mkdir -p "$LOGS_DIR"
LOG_FILE="${LOGS_DIR}/cleanup-${TIMESTAMP}.log"

# Logging functions
log() { echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"; }
success() { echo -e "${GREEN}✓${NC} $*" | tee -a "$LOG_FILE"; }
error() { echo -e "${RED}✗${NC} $*" | tee -a "$LOG_FILE"; }
warning() { echo -e "${YELLOW}⚠${NC} $*" | tee -a "$LOG_FILE"; }

################################################################################
# HELPER: Check if resource is idle
################################################################################

is_idle() {
    local resource_type="$1"
    local resource_name="$2"
    local last_activity_timestamp="$3"
    
    local last_activity_epoch=$(date -d "$last_activity_timestamp" +%s 2>/dev/null || echo 0)
    local current_epoch=$(date +%s)
    local idle_seconds=$((current_epoch - last_activity_epoch))
    
    if [[ $idle_seconds -ge $IDLE_THRESHOLD_SECS ]]; then
        echo "true"
        return 0
    else
        echo "false"
        return 1
    fi
}

################################################################################
# 1. CLEANUP: Docker Containers
################################################################################

cleanup_docker_containers() {
    log "Checking Docker containers for idle state..."
    
    if ! command -v docker &>/dev/null; then
        warning "Docker not installed, skipping"
        return 0
    fi
    
    # List all containers and check their last activity
    local containers=$(docker ps -a --format "table {{.Names}}\t{{.Status}}" 2>/dev/null || true)
    
    if [[ -z "$containers" ]]; then
        log "No containers found"
        return 0
    fi
    
    while IFS= read -r line; do
        if [[ -z "$line" || "$line" == NAMES* ]]; then
            continue
        fi
        
        local container_name=$(echo "$line" | awk '{print $1}')
        local status=$(echo "$line" | awk '{$1=""; print $0}' | xargs)
        
        # Skip if already stopped
        if [[ "$status" == *"Exited"* ]]; then
            log "Container $container_name already stopped"
            continue
        fi
        
        # Get container creation time as proxy for last activity
        local created_at=$(docker inspect --format='{{.Created}}' "$container_name" 2>/dev/null || echo "")
        
        if [[ -n "$created_at" ]]; then
            if is_idle "container" "$container_name" "$created_at"; then
                log "Stopping idle container: $container_name"
                docker stop "$container_name" 2>/dev/null && success "Stopped: $container_name" || error "Failed to stop: $container_name"
            fi
        fi
    done <<< "$containers"
}

################################################################################
# 2. CLEANUP: GCP Cloud Run Services (min-instances to 0)
################################################################################

cleanup_cloud_run() {
    log "Checking GCP Cloud Run services for idle state..."
    
    if ! command -v gcloud &>/dev/null; then
        warning "gcloud not installed, skipping Cloud Run cleanup"
        return 0
    fi
    
    local project_id=$(gcloud config get-value project 2>/dev/null || echo "")
    if [[ -z "$project_id" ]]; then
        warning "GCP project not configured"
        return 0
    fi
    
    local region="${GCP_REGION:-us-central1}"
    
    # List all Cloud Run services
    local services=$(gcloud run services list --region="$region" --format="value(metadata.name,metadata.creationTimestamp)" 2>/dev/null || true)
    
    if [[ -z "$services" ]]; then
        log "No Cloud Run services found"
        return 0
    fi
    
    while IFS=$'\t' read -r service_name created_at; do
        if [[ -z "$service_name" ]]; then
            continue
        fi
        
        # Check if service has been idle
        if is_idle "cloudrun" "$service_name" "$created_at"; then
            log "Scaling Cloud Run service to 0: $service_name"
            gcloud run services update "$service_name" \
                --region="$region" \
                --min-instances=0 \
                --quiet 2>/dev/null && success "Scaled to 0: $service_name" || error "Failed to scale: $service_name"
        fi
    done <<< "$services"
}

################################################################################
# 3. CLEANUP: GCP Cloud SQL (reduce tier to db-f1-micro in dev)
################################################################################

cleanup_cloud_sql() {
    log "Checking GCP Cloud SQL instances for idle state..."
    
    if ! command -v gcloud &>/dev/null; then
        warning "gcloud not installed, skipping Cloud SQL cleanup"
        return 0
    fi
    
    local project_id=$(gcloud config get-value project 2>/dev/null || echo "")
    if [[ -z "$project_id" ]]; then
        warning "GCP project not configured"
        return 0
    fi
    
    # List all Cloud SQL instances
    local instances=$(gcloud sql instances list --format="value(name,createTime)" 2>/dev/null || true)
    
    if [[ -z "$instances" ]]; then
        log "No Cloud SQL instances found"
        return 0
    fi
    
    while IFS=$'\t' read -r instance_name created_at; do
        if [[ -z "$instance_name" ]]; then
            continue
        fi
        
        # Skip production instances
        if [[ "$instance_name" == *"prod"* ]]; then
            log "Skipping production instance: $instance_name"
            continue
        fi
        
        # Check if idle
        if is_idle "cloudsql" "$instance_name" "$created_at"; then
            log "Downgrading idle Cloud SQL instance: $instance_name"
            
            # Get current tier
            local current_tier=$(gcloud sql instances describe "$instance_name" \
                --format="value(settings.tier)" 2>/dev/null || echo "")
            
            # Only downgrade if not already at minimum
            if [[ "$current_tier" != "db-f1-micro" ]]; then
                gcloud sql instances patch "$instance_name" \
                    --tier=db-f1-micro \
                    --quiet 2>/dev/null && success "Downgraded to db-f1-micro: $instance_name" || \
                    warning "Failed to downgrade: $instance_name (may be in use)"
            fi
        fi
    done <<< "$instances"
}

################################################################################
# 4. CLEANUP: GCP Redis (disable persistence in dev)
################################################################################

cleanup_redis() {
    log "Checking GCP Redis instances for idle state..."
    
    if ! command -v gcloud &>/dev/null; then
        warning "gcloud not installed, skipping Redis cleanup"
        return 0
    fi
    
    local project_id=$(gcloud config get-value project 2>/dev/null || echo "")
    if [[ -z "$project_id" ]]; then
        warning "GCP project not configured"
        return 0
    fi
    
    local region="${GCP_REGION:-us-central1}"
    
    # List all Redis instances
    local instances=$(gcloud redis instances list --region="$region" --format="value(name,createTime)" 2>/dev/null || true)
    
    if [[ -z "$instances" ]]; then
        log "No Redis instances found"
        return 0
    fi
    
    while IFS=$'\t' read -r instance_name created_at; do
        if [[ -z "$instance_name" ]]; then
            continue
        fi
        
        # Skip production instances
        if [[ "$instance_name" == *"prod"* ]]; then
            log "Skipping production instance: $instance_name"
            continue
        fi
        
        # Check if idle
        if is_idle "redis" "$instance_name" "$created_at"; then
            log "Disabling persistence on idle Redis instance: $instance_name"
            
            gcloud redis instances update "$instance_name" \
                --region="$region" \
                --disable-rdb \
                --quiet 2>/dev/null && success "Disabled RDB persistence: $instance_name" || \
                warning "Failed to update Redis: $instance_name"
        fi
    done <<< "$instances"
}

################################################################################
# 5. CLEANUP: Docker Compose Services (full shutdown)
################################################################################

cleanup_compose_services() {
    log "Checking docker-compose services for cleanup..."
    
    if ! command -v docker-compose &>/dev/null; then
        warning "docker-compose not installed, skipping"
        return 0
    fi
    
    # Find all docker-compose files
    local compose_files=$(find "$PROJECT_ROOT" -name "docker-compose*.yml" -type f 2>/dev/null | head -10)
    
    for compose_file in $compose_files; do
        if [[ -f "$compose_file" ]]; then
            log "Processing: $compose_file"
            
            # Get service status
            local services=$(docker-compose -f "$compose_file" ps --services 2>/dev/null || true)
            
            if [[ -z "$services" ]]; then
                continue
            fi
            
            # Check if all services are idle (no recent logs)
            local all_idle=true
            while IFS= read -r service; do
                if [[ -z "$service" ]]; then
                    continue
                fi
                
                # Check logs from last 5 minutes
                local recent_logs=$(docker-compose -f "$compose_file" logs --since "${IDLE_THRESHOLD_MINS}m" "$service" 2>/dev/null | wc -l || echo 0)
                
                if [[ $recent_logs -gt 0 ]]; then
                    all_idle=false
                    break
                fi
            done <<< "$services"
            
            if $all_idle; then
                log "All services in $compose_file appear idle, stopping..."
                docker-compose -f "$compose_file" down 2>/dev/null && \
                    success "Stopped compose services: $compose_file" || \
                    warning "Failed to stop: $compose_file"
            fi
        fi
    done
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}🛑 Idle Resource Cleanup - 5 Minute Threshold${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}\n"
    
    log "Starting cleanup process..."
    log "Idle threshold: ${IDLE_THRESHOLD_MINS} minutes (${IDLE_THRESHOLD_SECS} seconds)"
    
    cleanup_docker_containers
    cleanup_cloud_run
    cleanup_cloud_sql
    cleanup_redis
    cleanup_compose_services
    
    echo -e "\n${BLUE}════════════════════════════════════════════════════════════${NC}"
    success "Cleanup completed"
    log "Logs saved to: $LOG_FILE"
}

main "$@"
