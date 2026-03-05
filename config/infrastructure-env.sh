# ============================================================================
# INFRASTRUCTURE ENVIRONMENT CONFIGURATION
# ============================================================================
# Purpose: Enforce architectural boundaries and service deployments
# This file defines where each service MUST run and validates deployment
# ============================================================================

# ============================================================================
# CONTROL PLANE (192.168.168.31)
# ============================================================================
# Role: Management, CI/CD coordination, monitoring dashboards (access only)
# Services Allowed: kubectl, terraform, git, curl, monitoring clients (READ-ONLY)
# Services FORBIDDEN: Node.js apps, databases, workers, API servers
#
# CRITICAL: NO LONG-RUNNING PROCESSES BIND TO PORTS ON THIS NODE

export CONTROL_PLANE_IP="192.168.168.31"
export CONTROL_PLANE_ENABLED=false
export CONTROL_PLANE_ALLOW_SERVICES=false
export CONTROL_PLANE_FORBID_PORTS=(3919 3000 9095 9096 6379 5432)

# ============================================================================
# WORKER NODE (192.168.168.42)
# ============================================================================
# Role: ALL infrastructure services, databases, workers, APIs
# Services Required: Portal, Prometheus, Alertmanager, Grafana, Redis, APIs
# Network: Accessible from control plane for health checks and dashboards
#
# CRITICAL: THIS IS THE ONLY NODE WHERE SERVICES SHOULD RUN

export WORKER_NODE_IP="192.168.168.42"
export WORKER_NODE_ENABLED=true
export WORKER_NODE_SERVICES=(
  "portal:3919"
  "prometheus:9095"
  "alertmanager:9096"
  "grafana:3000"
  "redis:6379"
  "api-backend:8080"
  "provisioner-worker:8081"
)

# ============================================================================
# DEPLOYMENT ENFORCEMENT
# ============================================================================
# These variables MUST be set in all deployment contexts

export ENFORCE_WORKER_DEPLOYMENT=true       # Assert services on worker node
export REQUIRE_REMOTE_HOST=true             # Bind to 0.0.0.0, not localhost
export ALLOW_LOCALHOST_SERVICES=false       # npm dev/vite forbidden in production
export DEPLOYMENT_TARGET_NODE="192.168.168.42"

# ============================================================================
# NODE.JS REQUIREMENTS
# ============================================================================

export MIN_NODE_VERSION="20.19.0"           # Vite 7.3.1+ requirement
export RECOMMENDED_NODE_VERSION="22.0.0"    # LTS target
export SUPPORTED_NODE_VERSIONS=(
  "20.19.0"
  "22.0.0"
  "24.0.0"
)

# ============================================================================
# SERVICE PORT MAPPINGS
# ============================================================================
# Format: SERVICE_NAME_PORT=value
# All services must bind to 0.0.0.0:{PORT}, accessible from 192.168.168.42

export PORTAL_PORT="${PORT:-3919}"
export PORTAL_HOST="0.0.0.0"
export PORTAL_NODE="192.168.168.42"

export API_BACKEND_PORT="8080"
export API_BACKEND_HOST="0.0.0.0"
export API_BACKEND_NODE="192.168.168.42"

export PROMETHEUS_PORT="9095"
export PROMETHEUS_HOST="0.0.0.0"
export PROMETHEUS_NODE="192.168.168.42"

export ALERTMANAGER_PORT="9096"
export ALERTMANAGER_HOST="0.0.0.0"
export ALERTMANAGER_NODE="192.168.168.42"

export GRAFANA_PORT="3000"
export GRAFANA_HOST="0.0.0.0"
export GRAFANA_NODE="192.168.168.42"

export REDIS_PORT="6379"
export REDIS_HOST="127.0.0.1"  # Internal to worker node only
export REDIS_NODE="192.168.168.42"

# ============================================================================
# WORKER NODE ENDPOINT
# ============================================================================
# All clients must connect to services via this endpoint

export WORKER_NODE_ENDPOINT="192.168.168.42"
export API_BASE_URL="http://192.168.168.42:8080"
export PORTAL_URL="http://192.168.168.42:3919"
export PROMETHEUS_URL="http://192.168.168.42:9095"
export ALERTMANAGER_URL="http://192.168.168.42:9096"
export GRAFANA_URL="http://192.168.168.42:3000"

# ============================================================================
# VITE CONFIGURATION (ENFORCED)
# ============================================================================

export VITE_HOST="0.0.0.0"      # NOT localhost or 127.0.0.1
export VITE_PORT="${PORT:-3919}"
export VITE_USE_MOCK="false"
export VITE_API_BASE="http://192.168.168.42:8080"

# ============================================================================
# DOCKER & CONTAINER ENFORCEMENT
# ============================================================================

export DOCKER_COMPOSE_TARGET_NODE="192.168.168.42"
export CONTAINER_BIND_ADDRESS="0.0.0.0"
export FORBID_LOCALHOST_BINDING=true
export ENFORCE_NETWORK_POLICY=true

# ============================================================================
# GOVERNANCE & COMPLIANCE
# ============================================================================

export GOVERNANCE_POLICY_FILE="./INFRASTRUCTURE_GOVERNANCE.md"
export ENFORCE_ARCHITECTURE_BOUNDARIES=true
export COMPLIANCE_CHECK_FREQUENCY="300"  # 5 minutes
export AUTO_REMEDIATE_VIOLATIONS=true
export VIOLATION_ESCALATION_WEBHOOK="${SLACK_WEBHOOK_URL:-}"

# ============================================================================
# DEPLOYMENT VALIDATION
# ============================================================================

export VALIDATE_NODE_VERSION=true
export VALIDATE_ARCHITECTURE=true
export VALIDATE_PORT_BINDINGS=true
export VALIDATE_SERVICE_HEALTH=true
export STRICT_COMPLIANCE_MODE=false  # Set to true for zero-tolerance

# ============================================================================
# TERRAFORM CONSTRAINTS (if using infrastructure as code)
# ============================================================================

export TF_VAR_control_plane_ip="192.168.168.31"
export TF_VAR_worker_node_ip="192.168.168.42"
export TF_VAR_enforce_separation=true
export TF_VAR_service_node_binding="192.168.168.42"

# ============================================================================
# KUBERNETES CONSTRAINTS (if using Kubernetes)
# ============================================================================

export K8S_CONTROL_PLANE_NODE="not-applicable"  # Using single worker setup
export K8S_WORKER_NODES="192.168.168.42"
export K8S_ENFORCE_NODE_AFFINITY=true
export K8S_NETWORK_POLICY_ENABLED=true

# ============================================================================
# MONITORING & ALERTING
# ============================================================================

export COMPLIANCE_REPORT_SCHEDULE="0 0 * * *"  # Daily at midnight
export COMPLIANCE_ALERT_ON_VIOLATION=true
export COMPLIANCE_DASHBOARD_URL="http://192.168.168.42:3000/d/governance"

# ============================================================================
# DEVELOPMENT MODE RESTRICTIONS (LOCAL DEVELOPMENT ONLY)
# ============================================================================
# Even for development, these constraints should be enforced
# Use --allow-localhost flag only for LOCAL testing with justification

export ALLOW_LOCALHOST_DEV=false             # npm run dev will fail locally
export LOCALHOST_ALLOWED_UNTIL=""            # Leave empty = never allowed
export LOCALHOST_APPROVAL_ISSUE=""           # Reference GitHub issue if approved

# ============================================================================
# AUDIT & LOGGING
# ============================================================================

export GOVERNANCE_LOG_DIR="/var/log/governance"
export GOVERNANCE_AUDIT_ENABLED=true
export GOVERNANCE_AUDIT_RETENTION_DAYS="90"
export LOG_LEVEL="INFO"  # INFO, WARN, ERROR

echo "✓ Infrastructure environment configuration loaded"
echo "  Control Plane: $CONTROL_PLANE_IP (NO SERVICES)"
echo "  Worker Node: $WORKER_NODE_IP (ALL SERVICES)"
echo "  Min Node Version: $MIN_NODE_VERSION"
echo "  Governance Policy: ENFORCED"
