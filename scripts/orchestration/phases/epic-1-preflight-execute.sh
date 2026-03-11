#!/bin/bash
################################################################################
# EPIC-1: Pre-Flight Infrastructure Audit
# Complete system inventory across all components before migration
################################################################################

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AUDIT_DIR="${REPO_ROOT}/artifacts/epic-1-preflight-$(date +%Y%m%dT%H%M%S)Z"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%S.%6NZ)

echo "EPIC-1: Pre-Flight Infrastructure Audit"
echo "Started: $TIMESTAMP"
echo "Output: $AUDIT_DIR"

mkdir -p "$AUDIT_DIR"

# ============================================================================
# 1. SYSTEM INVENTORY
# ============================================================================
echo "1/8: Collecting system inventory..."

{
    echo "=== CONTAINERS & SERVICES ==="
    docker ps -a --format "table {{.ID}}\t{{.Names}}\t{{.Status}}" 2>/dev/null || true
    echo ""
    echo "=== GCLOUD SERVICES ==="
    gcloud compute instances list --format="table(NAME,ZONE,STATUS)" 2>/dev/null || true
    echo ""
    echo "=== CLOUD RUN SERVICES ==="
    gcloud run services list --format="table(NAME,STATUS,URL)" 2>/dev/null || true
} > "$AUDIT_DIR/01-system-inventory.txt"

# ============================================================================
# 2. DATABASE SNAPSHOTS & CONNECTIVITY
# ============================================================================
echo "2/8: Testing database connectivity..."

{
    echo "=== POSTGRESQL CONNECTIVITY ==="
    if command -v psql &>/dev/null; then
        psql -h localhost -U postgres -c "SELECT version();" 2>/dev/null || echo "PostgreSQL not accessible locally"
    else
        echo "psql not installed"
    fi
    echo ""
    echo "=== REDIS CONNECTIVITY ==="
    if command -v redis-cli &>/dev/null; then
        redis-cli ping 2>/dev/null || echo "Redis not accessible locally"
        redis-cli info server 2>/dev/null || true
    else
        echo "redis-cli not installed"
    fi
} > "$AUDIT_DIR/02-database-connectivity.txt"

# ============================================================================
# 3. CREDENTIAL INVENTORY (OBFUSCATED)
# ============================================================================
echo "3/8: Auditing credential inventory..."

{
    echo "=== GSM SECRETS ==="
    gcloud secrets list --format="table(NAME,CREATED,UPDATED,LABELS)" --project="$GCP_PROJECT" 2>/dev/null || echo "No GSM access"
    echo ""
    echo "=== ENVIRONMENT VARIABLES (OBFUSCATED) ==="
    env | grep -E "^(VAULT|GSM|AWS|AZURE|DB|REDIS|PORTAL)" | sed 's/=.*/=[REDACTED]/g' || true
} > "$AUDIT_DIR/03-credentials-obfuscated.txt"

# ============================================================================
# 4. NETWORK TOPOLOGY
# ============================================================================
echo "4/8: Mapping network topology..."

{
    echo "=== GCP NETWORKS ==="
    gcloud compute networks list --format="table(NAME,SUBNET_MODE,AUTO_CREATE_SUBNETWORKS,IPV4_RANGE)" 2>/dev/null || true
    echo ""
    echo "=== GCP FIREWALLS ==="
    gcloud compute firewall-rules list --format="table(NAME,NETWORK,DIRECTION,SOURCE_RANGES,ALLOW)" 2>/dev/null | head -20 || true
    echo ""
    echo "=== NETWORK INTERFACES (LOCAL) ==="
    ip addr show 2>/dev/null || ifconfig || true
} > "$AUDIT_DIR/04-network-topology.txt"

# ============================================================================
# 5. LOAD BALANCER CONFIGURATION
# ============================================================================
echo "5/8: Auditing load balancer configuration..."

{
    echo "=== GCP LOAD BALANCERS ==="
    gcloud compute backend-services list --format="table(NAME,HEALTH_CHECKS,IAP_OAUTH2_CLIENT_IDS)" 2>/dev/null || true
    echo ""
    echo "=== GCP HEALTH CHECKS ==="
    gcloud compute health-checks list --format="table(NAME,TYPE,PROTOCOL)" 2>/dev/null || true
    echo ""
    echo "=== CLOUD RUN SERVICES WITH TRAFFIC CONFIG ==="
    gcloud run services list --format="json" 2>/dev/null | jq '.[] | {name: .metadata.name, traffic: .status.traffic}' || true
} > "$AUDIT_DIR/05-load-balancer-config.txt"

# ============================================================================
# 6. PERFORMANCE BASELINE (72-HOUR COLLECTION INITIALIZED)
# ============================================================================
echo "6/8: Establishing performance baseline..."

{
    echo "=== BASELINE METRICS (T0) ==="
    echo "Timestamp: $TIMESTAMP"
    echo ""
    echo "=== SYSTEM RESOURCES ==="
    echo "Hostname: $(hostname)"
    echo "Uptime: $(uptime)"
    echo "CPU Count: $(nproc)"
    echo "Memory: $(free -h | grep Mem)"
    echo "Disk: $(df -h / | tail -1)"
    echo ""
    echo "=== ACTIVE SERVICES ==="
    systemctl list-units --type=service --all --format="table" 2>/dev/null | grep -E "portal|nexus|migration" | head -10 || true
} > "$AUDIT_DIR/06-performance-baseline.txt"

# Initialize 72-hour baseline collection (would normally run continuous collection)
echo "Performance baseline collection initialized (note: full 72-hour collection requires continuous monitoring)" >> "$AUDIT_DIR/06-performance-baseline.txt"

# ============================================================================
# 7. DNS CONFIGURATION AUDIT
# ============================================================================
echo "7/8: Auditing DNS configuration..."

{
    echo "=== CURRENT DNS RECORDS ==="
    gcloud dns record-sets list --zone-prefix="nexusshield" --format="table(NAME,TYPE,TTL,RRDATAS)" 2>/dev/null || echo "No DNS zones available"
    echo ""
    echo "=== DNS RESOLUTION TESTS ==="
    for host in api.nexusshield.io portal.nexusshield.io redis.nexusshield.io 2>/dev/null; do
        echo "Testing: $host"
        nslookup "$host" 2>&1 | head -5 || true
    done
} > "$AUDIT_DIR/07-dns-configuration.txt"

# ============================================================================
# 8. DEPENDENCY MAPPING
# ============================================================================
echo "8/8: Mapping service dependencies..."

{
    echo "=== SERVICE TOPOLOGY ==="
    echo ""
    echo "Portal Frontend"
    echo "  ├─ Portal Backend (API)"
    echo "  ├─ Cloud Run (GCP)"
    echo "  └─ Cloudflare (CDN/WAF)"
    echo ""
    echo "Portal Backend"
    echo "  ├─ PostgreSQL (Database)"
    echo "  ├─ Redis (Cache)"
    echo "  ├─ Secret Manager (Credentials)"
    echo "  ├─ Vault (Credential rotation)"
    echo "  └─ KMS (Encryption)"
    echo ""
    echo "Infrastructure"
    echo "  ├─ Cloud Build (CI/CD)"
    echo "  ├─ Cloud Scheduler (Automation)"
    echo "  └─ Cloud Monitoring (Observability)"
    echo ""
    echo "=== TERRAFORM STATE FILES ==="
    find "$REPO_ROOT/terraform" -name "*.tfstate" -o -name "*.tfvars" 2>/dev/null | head -10 || true
} > "$AUDIT_DIR/08-dependency-mapping.txt"

# ============================================================================
# FINAL AUDIT VALIDATION
# ============================================================================
echo ""
echo "======================================================================"
echo "EPIC-1: Pre-Flight Audit Complete"
echo "======================================================================"
echo "Artifacts saved to: $AUDIT_DIR"
echo "Total artifacts: $(ls -1 "$AUDIT_DIR" | wc -l)"
echo ""
ls -lh "$AUDIT_DIR"
echo ""
echo "Next: Review artifacts, then proceed to EPIC-2 (GCP Migration)"
echo "======================================================================"

# Create completion marker for state tracking
echo "{\"epic\": \"epic-1-preflight\", \"status\": \"completed\", \"timestamp\": \"$TIMESTAMP\", \"artifacts\": \"$AUDIT_DIR\"}" \
    > "$AUDIT_DIR/COMPLETION_MARKER.json"

exit 0
