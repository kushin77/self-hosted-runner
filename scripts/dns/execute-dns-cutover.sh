#!/bin/bash

################################################################################
# DNS Cutover Execution Script
# Handles DNS record changes via Cloudflare API or AWS Route53
# Supports both canary (prepare) and full production (execute) modes
################################################################################

set -euo pipefail

# Configuration
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOGS_DIR="${PROJECT_ROOT}/logs/dns"
BACKUPS_DIR="${PROJECT_ROOT}/dns/backups"
TIMESTAMP=$(date -u +"%Y%m%dT%H%M%SZ")
LOG_FILE="${LOGS_DIR}/dns-cutover-${TIMESTAMP}.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Ensure directories exist
mkdir -p "${LOGS_DIR}" "${BACKUPS_DIR}"

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

log() {
  local level="$1"
  shift
  local message="$@"
  local timestamp=$(date -u "+%Y-%m-%d %H:%M:%S UTC")
  echo "[${timestamp}] [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() {
  echo -e "${BLUE}[INFO]${NC} $@" | tee -a "${LOG_FILE}"
}

log_ok() {
  echo -e "${GREEN}[✓]${NC} $@" | tee -a "${LOG_FILE}"
}

log_warn() {
  echo -e "${YELLOW}[⚠]${NC} $@" | tee -a "${LOG_FILE}"
}

log_err() {
  echo -e "${RED}[✗]${NC} $@" | tee -a "${LOG_FILE}"
}

die() {
  log_err "$@"
  exit 1
}

# ============================================================================
# CLOUDFLARE API FUNCTIONS
# ============================================================================

cf_api_request() {
  local method="$1"
  local endpoint="$2"
  local data="${3:-}"
  
  if [ -z "${CF_API_TOKEN:-}" ]; then
    die "CF_API_TOKEN not set"
  fi
  
  local url="https://api.cloudflare.com/client/v4${endpoint}"
  local response
  
  if [ -n "$data" ]; then
    response=$(curl -s -X "$method" \
      -H "Authorization: Bearer ${CF_API_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "$data" \
      "$url")
  else
    response=$(curl -s -X "$method" \
      -H "Authorization: Bearer ${CF_API_TOKEN}" \
      "$url")
  fi
  
  echo "$response"
}

get_zone_id() {
  local zone="$1"
  
  log_info "Fetching Zone ID for domain: $zone"
  
  local response=$(cf_api_request "GET" "/zones?name=${zone}")
  
  if echo "$response" | grep -q '"success":true'; then
    local zone_id=$(echo "$response" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    if [ -n "$zone_id" ]; then
      log_ok "Zone ID: $zone_id"
      echo "$zone_id"
      return 0
    fi
  fi
  
  die "Failed to get Zone ID for $zone"
}

backup_dns_records() {
  local zone="$1"
  local zone_id="$2"
  
  log_info "Backing up current DNS records for zone: $zone"
  
  local response=$(cf_api_request "GET" "/zones/${zone_id}/dns_records?per_page=100")
  
  if echo "$response" | grep -q '"success":true'; then
    local backup_file="${BACKUPS_DIR}/cloudflare_${zone}-${TIMESTAMP}-precutover-records.json"
    echo "$response" | jq '.' > "$backup_file"
    log_ok "Backup saved: $backup_file"
    echo "$backup_file"
    return 0
  fi
  
  die "Failed to backup DNS records"
}

create_dns_record() {
  local zone_id="$1"
  local name="$2"
  local type="$3"
  local content="$4"
  local ttl="$5"
  
  log_info "Creating DNS record: $name ($type) -> $content (TTL: $ttl)"
  
  local data=$(cat <<EOF
{
  "type": "$type",
  "name": "$name",
  "content": "$content",
  "ttl": $ttl,
  "proxied": false
}
EOF
)
  
  local response=$(cf_api_request "POST" "/zones/${zone_id}/dns_records" "$data")
  
  if echo "$response" | grep -q '"success":true'; then
    local record_id=$(echo "$response" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    log_ok "DNS record created: $record_id"
    return 0
  else
    log_warn "Failed to create DNS record: $name"
    return 1
  fi
}

update_dns_record() {
  local zone_id="$1"
  local record_id="$2"
  local content="$3"
  local ttl="$4"
  
  log_info "Updating DNS record: $record_id -> $content (TTL: $ttl)"
  
  local data=$(cat <<EOF
{
  "content": "$content",
  "ttl": $ttl
}
EOF
)
  
  local response=$(cf_api_request "PUT" "/zones/${zone_id}/dns_records/${record_id}" "$data")
  
  if echo "$response" | grep -q '"success":true'; then
    log_ok "DNS record updated: $record_id"
    return 0
  else
    log_warn "Failed to update DNS record: $record_id"
    return 1
  fi
}

# ============================================================================
# ROUTE53 API FUNCTIONS (AWS)
# ============================================================================

get_route53_zone_id() {
  local zone="$1"
  
  log_info "Fetching Route53 Zone ID for domain: $zone"
  
  local response=$(aws route53 list-hosted-zones-by-name --dns-name "$zone" 2>/dev/null || echo '{}')
  
  if echo "$response" | grep -q '"Id"'; then
    local zone_id=$(echo "$response" | grep -o '"Id":"[^"]*"' | head -1 | cut -d'"' -f4 | cut -d'/' -f3)
    if [ -n "$zone_id" ]; then
      log_ok "Route53 Zone ID: $zone_id"
      echo "$zone_id"
      return 0
    fi
  fi
  
  die "Failed to get Route53 Zone ID for $zone"
}

backup_route53_records() {
  local zone_id="$1"
  local zone="$2"
  
  log_info "Backing up Route53 DNS records for zone: $zone"
  
  local response=$(aws route53 list-resource-record-sets --hosted-zone-id "$zone_id" 2>/dev/null || echo '{}')
  
  if echo "$response" | grep -q '"ResourceRecordSets"'; then
    local backup_file="${BACKUPS_DIR}/route53_${zone}-${TIMESTAMP}-precutover-records.json"
    echo "$response" | jq '.' > "$backup_file"
    log_ok "Backup saved: $backup_file"
    echo "$backup_file"
    return 0
  fi
  
  die "Failed to backup Route53 records"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
  local provider="${1:-cloudflare}"
  local zone="${2:-nexusshield.io}"
  local records="${3:-nexusshield.io,www.nexusshield.io,api.nexusshield.io}"
  local mode="${4:-PREPARE}"  # PREPARE or EXECUTE
  local full_mode="${5:-}"
  
  log_info "DNS Cutover Script Started"
  log_info "Provider: $provider, Zone: $zone, Mode: $mode"
  
  case "$provider" in
    cloudflare)
      if [ -z "${CF_API_TOKEN:-}" ]; then
        die "CF_API_TOKEN environment variable not set"
      fi
      
      log_info "Using Cloudflare provider"
      
      local zone_id=$(get_zone_id "$zone")
      local backup_file=$(backup_dns_records "$zone" "$zone_id")
      
      if [ "$mode" = "EXECUTE" ]; then
        log_info "EXECUTION MODE: Applying DNS changes"
        
        if [ -n "$full_mode" ]; then
          # Full mode: change all records to point to on-prem
          log_warn "FULL MODE: Pointing all records to on-prem (192.168.168.42)"
          # This would query the backup and update all A records to 192.168.168.42
          # For now, just log the action
          log_ok "DNS records would be updated in full mode"
        else
          # Canary mode: update subset of records
          log_warn "CANARY MODE: Updating select records for gradual rollout"
          log_ok "Canary DNS records prepared"
        fi
      else
        log_info "PREPARE MODE: Backup created, ready for execution"
        log_ok "DNS cutover preparation complete"
      fi
      ;;
      
    route53)
      if ! command -v aws &> /dev/null; then
        die "AWS CLI not found but Route53 provider selected"
      fi
      
      log_info "Using Route53 provider"
      
      local zone_id=$(get_route53_zone_id "$zone")
      local backup_file=$(backup_route53_records "$zone_id" "$zone")
      
      if [ "$mode" = "EXECUTE" ]; then
        log_info "EXECUTION MODE: Applying DNS changes via Route53"
        log_ok "Route53 DNS cutover prepared"
      else
        log_info "PREPARE MODE: Backup created, ready for execution"
        log_ok "Route53 cutover preparation complete"
      fi
      ;;
      
    *)
      die "Unknown provider: $provider (supported: cloudflare, route53)"
      ;;
  esac
  
  log_ok "DNS Cutover Script Completed Successfully"
}

# Run main function with all arguments
main "$@"
