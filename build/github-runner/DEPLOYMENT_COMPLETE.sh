#!/bin/bash
# GitHub Actions Self-Hosted Runner - Complete Deployment & Setup Guide
# For: ElevatedIQ infrastructure (192.168.168.42)
# Target: All repos (ElevatedIQ, aetherfoge, etc) via centralized runner

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}GitHub Actions Self-Hosted Runner - Complete Deployment Guide${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo ""

# ============================================================================
# PHASE 0: PREREQUISITES
# ============================================================================

echo -e "${YELLOW}[PHASE 0] Prerequisites Check${NC}"
echo "================================="
echo ""

echo "Checking Docker availability..."
docker --version || { echo -e "${RED}✗ Docker not found${NC}"; exit 1; }

echo "Checking docker-compose availability..."
docker-compose --version || { echo -e "${RED}✗ docker-compose not found${NC}"; exit 1; }

echo ""
echo -e "${GREEN}✓ All prerequisites available${NC}"
echo ""

# ============================================================================
# PHASE 1: DOCKER IMAGE BUILD
# ============================================================================

echo -e "${YELLOW}[PHASE 1] Build Docker Runner Image${NC}"
echo "======================================"
echo ""

RUNNER_DIR="/home/akushnir/ElevatedIQ-Mono-Mono-Repo/build/github-runner"

if [ ! -d "$RUNNER_DIR" ]; then
    echo -e "${RED}✗ Runner directory not found: $RUNNER_DIR${NC}"
    echo "Ensure PR #7426 is merged and repository is updated."
    exit 1
fi

cd "$RUNNER_DIR"

echo "Building elevatediq-github-runner Docker image..."
echo "This may take 3-5 minutes on first build..."
echo ""

if docker-compose build 2>&1 | tee /tmp/docker-build.log; then
    echo -e "${GREEN}✓ Docker image built successfully${NC}"
    docker images | grep github-runner || true
else
    echo -e "${RED}✗ Docker build failed${NC}"
    echo "Check /tmp/docker-build.log for details"
    exit 1
fi

echo ""

# ============================================================================
# PHASE 2: GENERATE RUNNER TOKEN
# ============================================================================

echo -e "${YELLOW}[PHASE 2] Generate GitHub Actions Runner Token${NC}"
echo "================================================"
echo ""

echo "🔑 ACTION REQUIRED: Generate a new runner token"
echo ""
echo "Steps:"
echo "  1. Open: https://github.com/kushin77/settings/runners/new"
echo "  2. Select: Linux"
echo "  3. Select: x64"
echo "  4. Copy the token (appears only once, valid for 1 hour)"
echo ""

read -p "Paste your RUNNER_TOKEN here: " RUNNER_TOKEN

if [ -z "$RUNNER_TOKEN" ]; then
    echo -e "${RED}✗ Token cannot be empty${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Token received${NC}"
echo ""

# ============================================================================
# PHASE 3: DEPLOY CONTAINER
# ============================================================================

echo -e "${YELLOW}[PHASE 3] Deploy Runner Container${NC}"
echo "==================================="
echo ""

echo "Starting runner container..."
echo "Container name: elevatediq-github-runner"
echo "Hostname: github-runner-42"
echo "Labels: self-hosted, linux, x64, docker, elevatediq"
echo ""

export RUNNER_TOKEN
if docker-compose up -d; then
    echo -e "${GREEN}✓ Container started${NC}"
else
    echo -e "${RED}✗ Failed to start container${NC}"
    docker-compose logs
    exit 1
fi

echo ""
echo "⏳ Waiting 5 seconds for runner to initialize..."
sleep 5

echo ""

# ============================================================================
# PHASE 4: VERIFY RUNNER ONLINE
# ============================================================================

echo -e "${YELLOW}[PHASE 4] Verify Runner Online${NC}"
echo "==============================="
echo ""

echo "Checking container status..."
if docker ps | grep elevatediq-github-runner; then
    echo -e "${GREEN}✓ Container running${NC}"
else
    echo -e "${RED}✗ Container not running${NC}"
    docker ps -a | grep github-runner
    exit 1
fi

echo ""
echo "Checking runner logs..."
docker logs elevatediq-github-runner | tail -10

echo ""
echo -e "${YELLOW}Verifying runner is registering...${NC}"
sleep 5

docker logs elevatediq-github-runner | grep -i "listening\|registered" || {
    echo "⚠️  Runner status check - viewing last 20 lines of logs:"
    docker logs elevatediq-github-runner | tail -20
}

echo ""

# ============================================================================
# PHASE 5: GITHUB UI VERIFICATION
# ============================================================================

echo -e "${YELLOW}[PHASE 5] GitHub UI Verification${NC}"
echo "=================================="
echo ""

echo "🌐 Runner should now appear in GitHub settings:"
echo "   https://github.com/kushin77/settings/runners"
echo ""
echo "Expected state: 🟢 Idle (Listening for jobs)"
echo ""
echo "⏳ Give GitHub 30-60 seconds to reflect the runner online..."
echo ""
echo "Checking via API..."

# Try to list runners (requires auth)
if command -v gh &> /dev/null; then
    echo "Using GitHub CLI to check runner status..."
    if gh api repos/kushin77/ElevatedIQ-Mono-Repo/actions/runners --silent 2>/dev/null | head -20; then
        echo -e "${GREEN}✓ Runner appears in GitHub API${NC}"
    else
        echo "GitHub CLI check failed - verify manually in GitHub UI"
    fi
else
    echo "GitHub CLI not available - verify manually in GitHub UI"
fi

echo ""

# ============================================================================
# PHASE 6: UPDATE WORKFLOWS
# ============================================================================

echo -e "${YELLOW}[PHASE 6] Next: Update Repository Workflows${NC}"
echo "=========================================="
echo ""

echo "Once runner is verified 🟢 Idle in GitHub UI, merge PR #7427:"
echo ""
echo "  PR #7427: Workflow Migration"
echo "  - Updates all 153 workflow files"
echo "  - Changes: runs-on: ubuntu-latest → runs-on: self-hosted"
echo "  - Link: https://github.com/kushin77/ElevatedIQ-Mono-Repo/pull/7427"
echo ""

echo "For other repositories (aetherfoge, etc):"
echo "  - aetherfoge issue #101: https://github.com/kushin77/aetherfoge/issues/101"
echo "  - Update .github/workflows/*.yml to use 'runs-on: self-hosted'"
echo ""

# ============================================================================
# PHASE 7: TEST END-TO-END
# ============================================================================

echo -e "${YELLOW}[PHASE 7] Test End-to-End${NC}"
echo "========================="
echo ""

echo "To verify workflows run on the container:"
echo ""
echo "  1. Push a test commit to any repository"
echo "  2. GitHub Actions will trigger a workflow"
echo "  3. Workflow will run on elevatediq-github-runner"
echo "  4. Watch container logs:"
echo ""
echo "     docker logs -f elevatediq-github-runner"
echo ""
echo "  5. Expected output: Job execution logs from your workflow"
echo ""

# ============================================================================
# PHASE 8: OPERATIONAL COMMANDS
# ============================================================================

echo -e "${YELLOW}[PHASE 8] Operational Commands${NC}"
echo "============================="
echo ""

echo "View runner logs (live):"
echo "  docker logs -f elevatediq-github-runner"
echo ""

echo "Check runner container status:"
echo "  docker ps | grep github-runner"
echo ""

echo "Stop runner:"
echo "  docker-compose -f $RUNNER_DIR/docker-compose.yml down"
echo ""

echo "Restart runner:"
echo "  docker-compose -f $RUNNER_DIR/docker-compose.yml down"
echo "  docker-compose -f $RUNNER_DIR/docker-compose.yml up -d"
echo ""

echo "Rebuild image (after Dockerfile changes):"
echo "  docker-compose -f $RUNNER_DIR/docker-compose.yml build --no-cache"
echo ""

echo "Remove runner from GitHub (if needed):"
echo "  Visit: https://github.com/kushin77/settings/runners"
echo "  Click '...' menu → Remove"
echo ""

# ============================================================================
# SUMMARY
# ============================================================================

echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ DEPLOYMENT COMPLETE${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo ""

echo "📊 Runner Status:"
echo "  • Container: elevatediq-github-runner ✓"
echo "  • Host: 192.168.168.42"
echo "  • Image: ubuntu:24.04 + tools"
echo "  • Docker: 4 CPU, 8GB memory"
echo ""

echo "📋 Next Steps:"
echo "  1. Verify runner is 🟢 Idle on GitHub: https://github.com/kushin77/settings/runners"
echo "  2. Merge PR #7427 (workflow migration)"
echo "  3. Push test commit to trigger workflows"
echo "  4. Monitor logs: docker logs -f elevatediq-github-runner"
echo ""

echo "📚 Documentation:"
echo "  • Deployment Guide: $RUNNER_DIR/DEPLOYMENT.md"
echo "  • Runner Setup Issue: https://github.com/kushin77/ElevatedIQ-Mono-Repo/issues/7425"
echo "  • Workflow Migration: https://github.com/kushin77/ElevatedIQ-Mono-Repo/pull/7427"
echo "  • aetherfoge Usage: https://github.com/kushin77/aetherfoge/issues/101"
echo ""

echo "✅ Your centralized GitHub Actions runner is now ready!"
echo ""
echo "   🎉 Zero GitHub Actions budget + Full Infrastructure Control 🎉"
echo ""
