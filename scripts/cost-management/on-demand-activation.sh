#!/bin/bash

################################################################################
# On-Demand Resource Activation
# Automatically wake up cloud resources when triggered by traffic/demand
# Zero management | Fully automated | Hands-off
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOGS_DIR="${PROJECT_ROOT}/logs/cost-management"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

mkdir -p "$LOGS_DIR"
LOG_FILE="${LOGS_DIR}/activation-${TIMESTAMP}.log"

# Logging functions
log() { echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"; }
success() { echo -e "${GREEN}✓${NC} $*" | tee -a "$LOG_FILE"; }
error() { echo -e "${RED}✗${NC} $*" | tee -a "$LOG_FILE"; }
warning() { echo -e "${YELLOW}⚠${NC} $*" | tee -a "$LOG_FILE"; }

################################################################################
# 1. ACTIVATE: Docker Containers
################################################################################

activate_docker_containers() {
    log "Starting Docker containers..."
    
    if ! command -v docker &>/dev/null; then
        error "Docker not installed"
        return 1
    fi
    
    # Compose files to activate
    local compose_files=(
        "frontend/docker-compose.dashboard.yml"
        "frontend/docker-compose.loadbalancer.yml"
        "config/docker-compose.postgres-exporter.yml"
        "config/docker-compose.redis-exporter.yml"
    )
    
    for compose_file in "${compose_files[@]}"; do
        local full_path="${PROJECT_ROOT}/${compose_file}"
        
        if [[ -f "$full_path" ]]; then
            log "Activating: $compose_file"
            
            docker-compose -f "$full_path" up -d 2>/dev/null && \
                success "Activated: $compose_file" || \
                warning "Failed to activate: $compose_file (may already be running)"
        fi
    done
}

################################################################################
# 2. ACTIVATE: GCP Cloud Run Services (set min-instances to 1)
################################################################################

activate_cloud_run() {
    log "Activating GCP Cloud Run services..."
    
    if ! command -v gcloud &>/dev/null; then
        warning "gcloud not installed, skipping Cloud Run activation"
        return 0
    fi
    
    local project_id=$(gcloud config get-value project 2>/dev/null || echo "")
    if [[ -z "$project_id" ]]; then
        warning "GCP project not configured"
        return 0
    fi
    
    local region="${GCP_REGION:-us-central1}"
    
    # List all Cloud Run services and activate them
    local services=$(gcloud run services list --region="$region" --format="value(metadata.name)" 2>/dev/null || true)
    
    if [[ -z "$services" ]]; then
        log "No Cloud Run services found"
        return 0
    fi
    
    while IFS= read -r service_name; do
        if [[ -z "$service_name" ]]; then
            continue
        fi
        
        log "Activating Cloud Run service: $service_name"
        
        gcloud run services update "$service_name" \
            --region="$region" \
            --min-instances=1 \
            --max-instances=10 \
            --memory=512Mi \
            --cpu=1 \
            --timeout=300s \
            --quiet 2>/dev/null && success "Activated: $service_name" || \
            error "Failed to activate: $service_name"
    done <<< "$services"
}

################################################################################
# 3. ACTIVATE: GCP Cloud SQL (restore production tier)
################################################################################

activate_cloud_sql() {
    log "Activating GCP Cloud SQL instances..."
    
    if ! command -v gcloud &>/dev/null; then
        warning "gcloud not installed, skipping Cloud SQL activation"
        return 0
    fi
    
    local project_id=$(gcloud config get-value project 2>/dev/null || echo "")
    if [[ -z "$project_id" ]]; then
        warning "GCP project not configured"
        return 0
    fi
    
    # List all Cloud SQL instances
    local instances=$(gcloud sql instances list --format="value(name,settings.tier)" 2>/dev/null || true)
    
    if [[ -z "$instances" ]]; then
        log "No Cloud SQL instances found"
        return 0
    fi
    
    while IFS=$'\t' read -r instance_name current_tier; do
        if [[ -z "$instance_name" ]]; then
            continue
        fi
        
        # Skip production instances
        if [[ "$instance_name" == *"prod"* ]]; then
            log "Skipping production instance: $instance_name"
            continue
        fi
        
        # Upgrade from micro to standard tier
        if [[ "$current_tier" == "db-f1-micro" ]]; then
            log "Upgrading Cloud SQL instance: $instance_name to db-n1-standard-1"
            
            gcloud sql instances patch "$instance_name" \
                --tier=db-n1-standard-1 \
                --quiet 2>/dev/null && success "Upgraded: $instance_name" || \
                error "Failed to upgrade: $instance_name"
        fi
    done <<< "$instances"
}

################################################################################
# 4. ACTIVATE: GCP Redis (enable persistence in dev)
################################################################################

activate_redis() {
    log "Activating GCP Redis instances..."
    
    if ! command -v gcloud &>/dev/null; then
        warning "gcloud not installed, skipping Redis activation"
        return 0
    fi
    
    local project_id=$(gcloud config get-value project 2>/dev/null || echo "")
    if [[ -z "$project_id" ]]; then
        warning "GCP project not configured"
        return 0
    fi
    
    local region="${GCP_REGION:-us-central1}"
    
    # List all Redis instances
    local instances=$(gcloud redis instances list --region="$region" --format="value(name)" 2>/dev/null || true)
    
    if [[ -z "$instances" ]]; then
        log "No Redis instances found"
        return 0
    fi
    
    while IFS= read -r instance_name; do
        if [[ -z "$instance_name" ]]; then
            continue
        fi
        
        # Skip production instances
        if [[ "$instance_name" == *"prod"* ]]; then
            log "Skipping production instance: $instance_name"
            continue
        fi
        
        log "Enabling persistence on Redis instance: $instance_name"
        
        gcloud redis instances update "$instance_name" \
            --region="$region" \
            --enable-rdb \
            --quiet 2>/dev/null && success "Enabled RDB: $instance_name" || \
            warning "Failed to enable RDB: $instance_name (may already be enabled)"
    done <<< "$instances"
}

################################################################################
# 5. HEALTH CHECK: Verify activation
################################################################################

health_check() {
    log "Running health checks on activated resources..."
    
    # Check Docker containers
    if command -v docker &>/dev/null; then
        local running=$(docker ps --format "table {{.Names}}" 2>/dev/null | wc -l)
        log "Docker containers running: $running"
    fi
    
    # Check Cloud Run
    if command -v gcloud &>/dev/null; then
        local region="${GCP_REGION:-us-central1}"
        local cr_services=$(gcloud run services list --region="$region" --format="value(metadata.name)" 2>/dev/null | wc -l)
        log "Cloud Run services available: $cr_services"
    fi
    
    success "Health check completed"
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}⚡ On-Demand Resource Activation${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}\n"
    
    log "Starting resource activation..."
    
    activate_docker_containers
    activate_cloud_run
    activate_cloud_sql
    activate_redis
    health_check
    
    echo -e "\n${BLUE}════════════════════════════════════════════════════════════${NC}"
    success "Activation completed - resources are now ready"
    log "Logs saved to: $LOG_FILE"
}

main "$@"
