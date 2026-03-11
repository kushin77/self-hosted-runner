#!/usr/bin/env bash
#
# Deploy NexusShield Dashboard (React) to Production
# CI-less deployment script - no GitHub Actions required
# Usage: ./scripts/deploy/deploy_dashboard.sh [remote_host] [api_url]
#
# Constraints:
#   - Immutable: Audit trail never modified
#   - Ephemeral: Old container removed before starting new one
#   - Idempotent: Safe to run multiple times
#   - No-Ops: Fully automated, zero manual intervention
#   - Hands-Off: Remote execution via SSH or localhost

set -euo pipefail

REMOTE="${1:-localhost}"
API_URL="${2:-http://localhost:8080}"
DEPLOY_DIR="/opt/nexusshield-dashboard"
IMAGE_NAME="nexusshield-dashboard"
CONTAINER_NAME="nexusshield-dashboard-prod"
PORT="${3:-3000}"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $(date -u +%Y-%m-%dT%H:%M:%SZ) $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $(date -u +%Y-%m-%dT%H:%M:%SZ) $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $(date -u +%Y-%m-%dT%H:%M:%SZ) $*"; }

log_info "Dashboard Deployment Starting"
log_info "Remote: $REMOTE | API: $API_URL | Port: $PORT"

# Helper function for remote commands
run_remote() {
  if [ "$REMOTE" == "localhost" ]; then
    bash -c "$1"
  else
    ssh "$REMOTE" bash -c "$1"
  fi
}

# 1. Build Docker image
log_info "Building Docker image..."
if [ "$REMOTE" == "localhost" ]; then
  docker build -f frontend/dashboard/Dockerfile \
    -t "$IMAGE_NAME:latest" \
    frontend/dashboard/ >/dev/null 2>&1 || {
    log_error "Docker build failed"
    exit 1
  }
else
  # For remote, we need to either build there or use Docker buildx
  log_info "Syncing files to remote and building..."
  scp -r frontend/dashboard "$REMOTE:/tmp/dashboard_build/"
  ssh "$REMOTE" "cd /tmp/dashboard_build && docker build -t $IMAGE_NAME:latest . >/dev/null 2>&1"
fi

log_success "Docker image built"

# 2. Stop and remove old container (ephemeral cleanup)
log_info "Stopping old container (if running)..."
run_remote "docker rm -f $CONTAINER_NAME 2>/dev/null || true"
log_success "Old container cleaned up"

# 3. Start new container
log_info "Starting new container..."
run_remote "docker run -d \
  --name $CONTAINER_NAME \
  --restart=unless-stopped \
  -p $PORT:3000 \
  -e REACT_APP_API_URL='$API_URL' \
  --health-cmd='curl -f http://localhost:3000/ || exit 1' \
  --health-interval=30s \
  --health-timeout=3s \
  --health-start-period=10s \
  --health-retries=3 \
  $IMAGE_NAME:latest" || {
  log_error "Failed to start container"
  exit 1
}

log_success "Container started"

# 4. Wait for health check to pass
log_info "Waiting for container health check..."
for i in $(seq 1 30); do
  HEALTH=$(run_remote "docker inspect --format='{{.State.Health.Status}}' $CONTAINER_NAME 2>/dev/null || echo 'starting'")
  if [ "$HEALTH" == "healthy" ]; then
    log_success "Container is healthy"
    break
  fi
  if [ $i -eq 30 ]; then
    log_error "Container health check failed after 30 seconds"
    exit 1
  fi
  sleep 1
done

# 5. Verify API connectivity
log_info "Verifying API connectivity..."
API_HOST=$(echo "$API_URL" | sed 's|http://||g' | cut -d':' -f1)
API_PORT=$(echo "$API_URL" | sed 's|.*:||g')
if [ "$API_PORT" == "$API_URL" ]; then
  API_PORT="80"
fi

if run_remote "curl -sf http://$API_HOST:$API_PORT/health >/dev/null 2>&1"; then
  log_success "API connectivity verified"
else
  log_warning "API connectivity check failed (may be expected if API behind firewall)"
fi

# 6. Configure systemd service (for restart on reboot)
log_info "Installing systemd service..."
run_remote "sudo tee /etc/systemd/system/nexusshield-dashboard.service >/dev/null <<'EOF'
[Unit]
Description=NexusShield Migration Dashboard
After=docker.service
Requires=docker.service

[Service]
Type=simple
ExecStart=/bin/bash -c 'docker run --rm -p $PORT:3000 -e REACT_APP_API_URL=$API_URL $IMAGE_NAME:latest'
Restart=unless-stopped
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF"

run_remote "sudo systemctl daemon-reload && sudo systemctl enable nexusshield-dashboard.service" || true

log_success "Systemd service configured"

# 7. Log deployment info
log_info "Deployment completed successfully"
echo ""
echo "═════════════════════════════════════════════════════════"
echo "Dashboard Deployment Summary"
echo "═════════════════════════════════════════════════════════"
echo "Host: $REMOTE"
echo "Dashboard URL: http://$REMOTE:$PORT"
echo "API Backend: $API_URL"
echo "Container: $CONTAINER_NAME"
echo "Image: $IMAGE_NAME:latest"
echo ""
echo "Next steps:"
echo "  1. Open: http://$REMOTE:$PORT"
echo "  2. Enter admin key when prompted"
echo "  3. View migration jobs and metrics"
echo ""
echo "For logs:"
echo "  ssh $REMOTE 'docker logs -f $CONTAINER_NAME'"
echo ""
echo "To stop:"
echo "  ssh $REMOTE 'docker stop $CONTAINER_NAME'"
echo "═════════════════════════════════════════════════════════"

log_success "Dashboard is live and ready"
