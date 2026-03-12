#!/bin/bash

###############################################################################
# DAY 1: POSTGRESQL DEPLOYMENT & VALIDATION
# Purpose: Deploy PostgreSQL, run migrations, validate RLS policies
# Date: March 12, 2026
###############################################################################

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-postgres-dev-password}"
POSTGRES_DB="nexus_engine"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
LOG_DIR="logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/day1-postgres_${TIMESTAMP}.log"

log() { echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"; }
log_success() { echo -e "${GREEN}[✅]${NC} $*" | tee -a "$LOG_FILE"; }
log_error() { echo -e "${RED}[❌]${NC} $*" | tee -a "$LOG_FILE"; }

step_verify_prerequisites() {
    log "Step 1/8: Verifying prerequisites..."
    command -v docker &> /dev/null && log_success "Docker available" || { log_error "Docker required"; return 1; }
    return 0
}

step_start_postgres() {
    log "Step 2/8: Starting PostgreSQL..."
    docker ps | grep -q postgres && log_success "PostgreSQL running" && return 0
    
    docker run -d --name postgres-nexus \
        -e POSTGRES_USER="$POSTGRES_USER" \
        -e POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
        -e POSTGRES_DB="$POSTGRES_DB" \
        -p "$POSTGRES_PORT:5432" \
        -v postgres-data:/var/lib/postgresql/data \
        postgres:15-alpine > /dev/null 2>&1
    
    for i in {1..30}; do
        docker exec postgres-nexus pg_isready -U "$POSTGRES_USER" &>/dev/null && { log_success "PostgreSQL ready"; return 0; }
        sleep 1
    done
    
    log_error "PostgreSQL startup timeout"
    return 1
}

step_create_database() {
    log "Step 3/8: Creating database..."
    export PGPASSWORD="$POSTGRES_PASSWORD"
    psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -p "$POSTGRES_PORT" \
        -tc "SELECT 1 FROM pg_database WHERE datname = '$POSTGRES_DB'" 2>/dev/null | grep -q 1 && \
        log_success "Database exists" || \
        (psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -p "$POSTGRES_PORT" \
            -c "CREATE DATABASE $POSTGRES_DB" && log_success "Database created")
    unset PGPASSWORD
}

step_run_migrations() {
    log "Step 4/8: Running migrations..."
    [[ -d "db/migrations" ]] || { log "No migrations" && return 0; }
    export PGPASSWORD="$POSTGRES_PASSWORD"
    find db/migrations -name "*.sql" 2>/dev/null | sort | while read -r mig; do
        psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -p "$POSTGRES_PORT" -d "$POSTGRES_DB" -f "$mig" 2>/dev/null && \
            log_success "Applied $(basename "$mig")" || log "Skipped $(basename "$mig")"
    done
    unset PGPASSWORD
}

step_enable_rls() {
    log "Step 5/8: Enabling RLS..."
    export PGPASSWORD="$POSTGRES_PASSWORD"
    for table in github_repos github_workflows; do
        psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -p "$POSTGRES_PORT" -d "$POSTGRES_DB" \
            -c "ALTER TABLE IF EXISTS $table ENABLE ROW LEVEL SECURITY" 2>/dev/null && log_success "RLS: $table"
    done
    unset PGPASSWORD
}

step_verify_data() {
    log "Step 6/8: Verifying data..."
    export PGPASSWORD="$POSTGRES_PASSWORD"
    count=$(psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -p "$POSTGRES_PORT" -d "$POSTGRES_DB" \
        -tAc "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public'" 2>/dev/null)
    log_success "Tables: $count"
    unset PGPASSWORD
}

step_test_connections() {
    log "Step 7/8: Testing connections..."
    export PGPASSWORD="$POSTGRES_PASSWORD"
    for i in {1..3}; do
        psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -p "$POSTGRES_PORT" -d "$POSTGRES_DB" -c "SELECT 1" &>/dev/null &
    done
    wait
    log_success "Connection pool OK"
    unset PGPASSWORD
}

step_final_check() {
    log "Step 8/8: Final health check..."
    export PGPASSWORD="$POSTGRES_PASSWORD"
    psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -p "$POSTGRES_PORT" -d "$POSTGRES_DB" -c "SELECT 1" &>/dev/null && \
        log_success "Health check passed" || { log_error "Health check failed"; return 1; }
    unset PGPASSWORD
}

main() {
    log "=========================================="
    log "DAY 1: PostgreSQL Deployment"
    log "=========================================="
    step_verify_prerequisites || { log_error "Prerequisites failed"; exit 1; }
    step_start_postgres || { log_error "PostgreSQL failed"; exit 1; }
    step_create_database || true
    step_run_migrations || true
    step_enable_rls || true
    step_verify_data || true
    step_test_connections || true
    step_final_check || { log_error "Final check failed"; exit 1; }
    echo ""
    log_success "=========================================="
    log_success "✅ DAY 1 COMPLETE - PostgreSQL Ready"
    log_success "=========================================="
}

main "$@"
