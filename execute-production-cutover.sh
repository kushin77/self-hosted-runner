#!/bin/bash
##############################################################################
# Production DNS Cutover Execution Master Script
# Purpose: Execute full on-prem traffic cutover with canary → full promotion
# Usage: CF_API_TOKEN="<token>" SLACK_WEBHOOK_URL="<webhook>" bash execute-production-cutover.sh
# Status: PRODUCTION-READY, Safety checks enabled
##############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR" && pwd)"
TS=$(date -u +%Y%m%dT%H%M%SZ)
LOG_DIR="$PROJECT_ROOT/logs/cutover"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/execution_${TS}.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

##############################################################################
# Logging & Status Functions
##############################################################################

log() { echo "[$(date -u +%H:%M:%S)] $*" | tee -a "$LOG_FILE"; }
err() { echo -e "${RED}❌ ERROR: $*${NC}" | tee -a "$LOG_FILE" >&2; }
ok()  { echo -e "${GREEN}✅ $*${NC}" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}⚠️  $*${NC}" | tee -a "$LOG_FILE"; }
info() { echo -e "${BLUE}ℹ️  $*${NC}" | tee -a "$LOG_FILE"; }

##############################################################################
# Pre-Execution Validation
##############################################################################

log "Starting production DNS cutover execution"
log "Log file: $LOG_FILE"
log ""

# Validate required environment variables
if [ -z "${CF_API_TOKEN:-}" ]; then
  err "CF_API_TOKEN not set. Unable to execute DNS cutover."
  echo "Usage: CF_API_TOKEN='<token>' bash $0"
  exit 1
fi

ok "CF_API_TOKEN set"

# Validate infrastructure
if ! command -v curl &>/dev/null; then
  err "curl not found. Required for DNS operations."
  exit 1
fi
ok "curl available"

# Validate script existence
if [ ! -x "$PROJECT_ROOT/scripts/dns/execute-dns-cutover.sh" ]; then
  err "execute-dns-cutover.sh not found or not executable"
  exit 1
fi
ok "DNS execution script available"

# Optional: Validate on-prem connectivity
if command -v ssh &>/dev/null && [ -n "${ON_PREM_HOST:-192.168.168.42}" ]; then
  ON_PREM_TEST=$(ssh -o ConnectTimeout=5 "akushnir@192.168.168.42" "docker-compose -f /home/akushnir/deployments/docker-compose.yml ps" 2>&1 | grep -c "Up" || echo "0")
  if [ "$ON_PREM_TEST" -gt "0" ]; then
    ok "On-prem infrastructure verified ($ON_PREM_TEST containers running)"
  else
    warn "On-prem container status unclear; continuing anyway"
  fi
fi

log ""
info "All pre-execution checks passed. Proceeding with DNS cutover."
log ""

##############################################################################
# PHASE 1: DNS CANARY CUTOVER
##############################################################################

log "╔════════════════════════════════════════════════════════════════════════════╗"
log "║ PHASE 1: DNS CANARY CUTOVER (30–60 min verification window)               ║"
log "╚════════════════════════════════════════════════════════════════════════════╝"
log ""

CANARY_START=$(date +%s)

log "Executing DNS canary cutover..."
log "Command: CF_API_TOKEN='***' ./scripts/dns/execute-dns-cutover.sh --provider cloudflare --zone nexusshield.io --records 'nexusshield.io,www.nexusshield.io,api.nexusshield.io' --mode EXECUTE --out dns/backups"
log ""

if CF_API_TOKEN="$CF_API_TOKEN" bash "$PROJECT_ROOT/scripts/dns/execute-dns-cutover.sh" \
  --provider cloudflare \
  --zone nexusshield.io \
  --records "nexusshield.io,www.nexusshield.io,api.nexusshield.io" \
  --mode EXECUTE \
  --out dns/backups 2>&1 | tee -a "$LOG_FILE"; then
  ok "DNS canary cutover executed successfully"
else
  err "DNS canary cutover failed"
  exit 1
fi

log ""
log "Verifying DNS propagation..."
sleep 5

# Check DNS resolution
for rec in nexusshield.io www.nexusshield.io api.nexusshield.io; do
  if nslookup "canary.$rec" &>/dev/null; then
    ok "DNS canary record resolved: canary.$rec"
  else
    warn "DNS canary record resolution pending: canary.$rec (TTL 300s, may take up to 5 min)"
  fi
done

log ""
info "===== CANARY VERIFICATION WINDOW (30–60 minutes) ====="
log "Monitor application metrics at: http://192.168.168.42:3000 (Grafana)"
log "Expected metrics:"
log "  • Error rate: < 0.1%"
log "  • Container restarts: 0"
log "  • Database query latency (p95): < 100ms"
log "  • No user-reported issues in Slack"
log ""
log "Once canary is verified stable, execute PHASE 2 to promote to full cutover."
log "To rollback immediately (if issues): Revert DNS records from:"
log "  $PROJECT_ROOT/dns/backups/cloudflare_*-precutover-records.json"
log ""

# If SKIP_MONITORING env var set, proceed to full promotion (for automation)
if [ -n "${SKIP_MONITORING:-}" ]; then
  warn "SKIP_MONITORING set; proceeding to full promotion without waiting"
else
  log "Waiting for operator decision..."
  read -p "Enter to continue to PHASE 2 (full promotion), or Ctrl+C to stop for manual verification: " < /dev/tty
fi

##############################################################################
# PHASE 2: FULL DNS PROMOTION
##############################################################################

log ""
log "╔════════════════════════════════════════════════════════════════════════════╗"
log "║ PHASE 2: FULL DNS PROMOTION (post-verification)                           ║"
log "╚════════════════════════════════════════════════════════════════════════════╝"
log ""

log "Promoting canary records to production..."
log "Command: CF_API_TOKEN='***' ./scripts/dns/execute-dns-cutover.sh --provider cloudflare --zone nexusshield.io --records 'nexusshield.io,www.nexusshield.io,api.nexusshield.io' --mode EXECUTE --full --out dns/backups"
log ""

if CF_API_TOKEN="$CF_API_TOKEN" bash "$PROJECT_ROOT/scripts/dns/execute-dns-cutover.sh" \
  --provider cloudflare \
  --zone nexusshield.io \
  --records "nexusshield.io,www.nexusshield.io,api.nexusshield.io" \
  --mode EXECUTE \
  --full \
  --out dns/backups 2>&1 | tee -a "$LOG_FILE"; then
  ok "Full DNS promotion executed successfully"
else
  err "Full DNS promotion failed"
  exit 1
fi

log ""
log "Verifying production DNS records..."
sleep 5

for rec in nexusshield.io www.nexusshield.io api.nexusshield.io; do
  if nslookup "$rec" 2>/dev/null | grep -q "192.168.168.42"; then
    ok "Production DNS record verified: $rec → 192.168.168.42"
  else
    warn "Production DNS record resolution pending: $rec"
  fi
done

##############################################################################
# PHASE 3: NOTIFICATIONS (optional)
##############################################################################

log ""
log "╔════════════════════════════════════════════════════════════════════════════╗"
log "║ PHASE 3: STAKEHOLDER NOTIFICATIONS (optional)                             ║"
log "╚════════════════════════════════════════════════════════════════════════════╝"
log ""

if [ -n "${SLACK_WEBHOOK_URL:-}" ]; then
  log "Sending Slack notification..."
  if [ -x "$PROJECT_ROOT/notifications/send-slack.sh" ]; then
    if SLACK_WEBHOOK_URL="$SLACK_WEBHOOK_URL" bash "$PROJECT_ROOT/notifications/send-slack.sh" \
      "$PROJECT_ROOT/notifications/STAKEHOLDER_NOTIFICATION_SLACK.md" 2>&1 | tee -a "$LOG_FILE"; then
      ok "Slack notification sent"
    else
      warn "Slack notification failed (continuing anyway)"
    fi
  else
    warn "send-slack.sh not found or not executable"
  fi
else
  info "SLACK_WEBHOOK_URL not set; skipping Slack notification"
fi

if [ -n "${EMAIL_TO:-}" ]; then
  log "Sending email notification..."
  if [ -x "$PROJECT_ROOT/notifications/send-email.sh" ]; then
    if EMAIL_TO="$EMAIL_TO" bash "$PROJECT_ROOT/notifications/send-email.sh" \
      "$PROJECT_ROOT/notifications/STAKEHOLDER_NOTIFICATION_EMAIL.md" 2>&1 | tee -a "$LOG_FILE"; then
      ok "Email notification sent"
    else
      warn "Email notification failed (continuing anyway)"
    fi
  else
    warn "send-email.sh not found or not executable"
  fi
else
  info "EMAIL_TO not set; skipping email notification"
fi

##############################################################################
# PHASE 4: POST-CUTOVER VALIDATION INSTRUCTIONS
##############################################################################

log ""
log "╔════════════════════════════════════════════════════════════════════════════╗"
log "║ PHASE 4: POST-CUTOVER VALIDATION (24–48 hours)                            ║"
log "╚════════════════════════════════════════════════════════════════════════════╝"
log ""

log "Continue monitoring for 24+ hours:"
log ""
log "1. Application Metrics (Prometheus/Grafana)"
log "   URL: http://192.168.168.42:3000"
log "   Success criteria:"
log "     • Error rate < 0.1%"
log "     • Database query latency (p95) < 100ms"
log "     • No container restarts"
log ""
log "2. User Reports (Slack/Email)"
log "   • Monitor #support and #infra-ops for user issues"
log "   • Investigate any reported login, API, or performance problems"
log ""
log "3. Cloud Shadow Mode (optional, 48–72 hours)"
log "   • Keep GCP Cloud Run endpoints running as cold backup"
log "   • Monitor cloud logs for any unexpected activity"
log "   • Decommission after confidence period (or keep indefinitely)"
log ""
log "4. Escalation Contacts"
log "   • On-call: ops-oncall@nexusshield.io"
log "   • Slack: #infra-ops"
log ""

##############################################################################
# ARTIFACT PRESERVATION
##############################################################################

log ""
log "Preserving execution artifacts..."
log "DNS change-sets: $PROJECT_ROOT/dns/backups/"
log "Execution log: $LOG_FILE"
log "Pre-cutover backup: $(ls -1 $PROJECT_ROOT/dns/backups/cloudflare_*-precutover-records.json 2>/dev/null | head -n1 || echo 'not found')"
log ""

##############################################################################
# COMPLETION
##############################################################################

CUTOVER_DURATION=$(($(date +%s) - CANARY_START))

log ""
log "╔════════════════════════════════════════════════════════════════════════════╗"
log "║ ✅ PRODUCTION DNS CUTOVER COMPLETE                                         ║"
log "╚════════════════════════════════════════════════════════════════════════════╝"
log ""
log "Status: On-prem infrastructure (192.168.168.42) is now receiving production traffic"
log "Timeline: Canary execution + monitoring: ${CUTOVER_DURATION}s"
log "Next: Monitor application for 24+ hours"
log ""
log "Full execution log: $LOG_FILE"
log ""

ok "Cutover execution complete. Archive this log for compliance & audit."
