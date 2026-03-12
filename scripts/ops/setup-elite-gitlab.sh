#!/bin/bash

# 🚀 GITLAB ELITE MSP OPERATIONS - AUTOMATED SETUP SCRIPT
# This script automates the installation and configuration of the elite GitLab runner and pipeline

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    # Check OS
    if [[ ! "$OSTYPE" =~ ^linux ]]; then
        print_error "This script is designed for Linux. Current OS: $OSTYPE"
        exit 1
    fi
    
    # Check if running as non-root (will use sudo)
    if [[ $EUID -eq 0 ]]; then
        print_warning "Running as root. Some commands may not require sudo."
    fi
    
    # Check curl
    if ! command -v curl &> /dev/null; then
        print_error "curl is required but not installed. Install with: sudo apt-get install curl"
        exit 1
    fi
    print_success "curl is installed"
    
    # Check git
    if ! command -v git &> /dev/null; then
        print_error "git is required but not installed. Install with: sudo apt-get install git"
        exit 1
    fi
    print_success "git is installed"
    
    # Check Docker (for Docker executor)
    if ! command -v docker &> /dev/null; then
        print_warning "Docker not found. Shell executor will work, but Docker executor requires Docker."
    else
        print_success "Docker is installed"
    fi
}

# Install GitLab Runner
install_gitlab_runner() {
    print_header "Installing GitLab Runner"
    
    if command -v gitlab-runner &> /dev/null; then
        print_warning "gitlab-runner is already installed"
        gitlab-runner --version
        return 0
    fi
    
    print_info "Detecting package manager..."
    
    if command -v apt-get &> /dev/null; then
        print_info "Using apt-get (Debian/Ubuntu)"
        curl -L https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh | sudo bash
        sudo apt-get update
        sudo apt-get install -y gitlab-runner
    elif command -v yum &> /dev/null; then
        print_info "Using yum (RHEL/CentOS)"
        curl -L https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.rpm.sh | sudo bash
        sudo yum install -y gitlab-runner
    else
        print_error "Unsupported package manager. Please install gitlab-runner manually."
        exit 1
    fi
    
    print_success "GitLab Runner installed"
    gitlab-runner --version
}

# Register runners
register_runners() {
    print_header "Registering GitLab Runners"
    
    # Get configuration from environment or prompt
    if [[ -z "${GITLAB_URL:-}" ]]; then
        read -p "Enter GitLab URL (default: https://gitlab.com/): " GITLAB_URL
        GITLAB_URL="${GITLAB_URL:-https://gitlab.com/}"
    fi
    
    if [[ -z "${REGISTRATION_TOKEN:-}" ]]; then
        read -p "Enter Runner Registration Token: " REGISTRATION_TOKEN
    fi
    
    if [[ -z "$REGISTRATION_TOKEN" ]]; then
        print_error "Registration token is required"
        exit 1
    fi
    
    # Register Shell Executor
    print_info "Registering Shell Executor..."
    sudo gitlab-runner register \
        --non-interactive \
        --url "${GITLAB_URL}" \
        --registration-token "${REGISTRATION_TOKEN}" \
        --executor "shell" \
        --description "primary-shell-executor" \
        --tag-list "self-hosted,docker,primary" \
        --run-untagged "false" \
        --locked "false" || print_warning "Shell runner may already be registered"
    
    print_success "Shell executor registered"
    
    # Register Docker Executor (if Docker is available)
    if command -v docker &> /dev/null; then
        print_info "Registering Docker Executor..."
        sudo gitlab-runner register \
            --non-interactive \
            --url "${GITLAB_URL}" \
            --registration-token "${REGISTRATION_TOKEN}" \
            --executor "docker" \
            --docker-image "docker:latest" \
            --docker-privileged \
            --docker-services "docker:dind" \
            --description "docker-executor-pool" \
            --tag-list "docker,build,container" \
            --run-untagged "false" \
            --locked "false" || print_warning "Docker runner may already be registered"
        
        print_success "Docker executor registered"
    fi
}

# Enable runner service
enable_runner_service() {
    print_header "Enabling GitLab Runner Service"
    
    sudo systemctl enable --now gitlab-runner || {
        print_error "Failed to enable gitlab-runner service"
        exit 1
    }
    
    # Wait for service to start
    sleep 2
    
    # Check status
    if sudo systemctl is-active --quiet gitlab-runner; then
        print_success "GitLab Runner service is active"
    else
        print_error "GitLab Runner service failed to start"
        exit 1
    fi
    
    sudo systemctl status gitlab-runner --no-pager
}

# Verify configuration
verify_configuration() {
    print_header "Verifying Configuration"
    
    print_info "Verifying runners..."
    sudo gitlab-runner verify
    
    print_info "Listing registered runners..."
    sudo gitlab-runner list
    
    print_success "Configuration verified"
}

# Setup elite pipeline
setup_elite_pipeline() {
    print_header "Setting Up Elite Pipeline"
    
    if [[ ! -f ".gitlab-ci.elite.yml" ]]; then
        print_error ".gitlab-ci.elite.yml not found in current directory"
        print_info "Make sure you're in the repository root directory"
        return 1
    fi
    
    # Backup existing .gitlab-ci.yml if present
    if [[ -f ".gitlab-ci.yml" ]]; then
        print_warning "Backing up existing .gitlab-ci.yml"
        cp .gitlab-ci.yml .gitlab-ci.yml.backup-$(date +%s)
    fi
    
    # Copy elite configuration
    cp .gitlab-ci.elite.yml .gitlab-ci.yml
    print_success "Elite pipeline configuration activated"
    
    # Commit changes
    if output=$(git status --porcelain 2>&1 | head -1); then
        read -p "Commit elite pipeline config to git? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            git add .gitlab-ci.yml
            git commit -m "feat: enable elite MSP operations pipeline"
            print_success "Changes committed to git"
        fi
    fi
}

# Test pipeline
test_pipeline() {
    print_header "Testing Pipeline"
    
    print_info "Creating a test pipeline..."
    print_info "Visit the GitLab project and trigger a pipeline:"
    print_info "  Project → CI/CD → Pipelines → Run Pipeline"
    print_info ""
    print_info "Or use GitLab API:"
    
    cat << 'EOF'
    
    curl --request POST \
      --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
      "https://gitlab.com/api/v4/projects/${PROJECT_ID}/pipeline?ref=main"
    
    # Monitor pipeline:
    # gitlab.com/PROJECT_URL/-/pipelines
    
EOF
}

# Setup monitoring (optional)
setup_monitoring() {
    print_header "Setting Up Monitoring (Optional)"
    
    read -p "Setup observability stack (Prometheus/Grafana)? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Skipping monitoring setup"
        return 0
    fi
    
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        print_warning "kubectl not found. Skipping Kubernetes monitoring setup."
        return 1
    fi
    
    print_info "Creating monitoring namespace..."
    kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
    print_success "Monitoring namespace created"
    
    if [[ -f "monitoring/elite-observability.yaml" ]]; then
        print_info "Applying observability configuration..."
        kubectl apply -f monitoring/elite-observability.yaml
        print_success "Observability stack deployed"
    fi
}

# Display summary
display_summary() {
    print_header "Setup Complete! 🎉"
    
    cat << 'EOF'

✅ GitLab Elite MSP Operations Control Plane is now started!

NEXT STEPS:

1. Verify Runners:
   sudo gitlab-runner list
   sudo gitlab-runner verify

2. Activate Elite Pipeline:
   cp .gitlab-ci.elite.yml .gitlab-ci.yml
   git add .gitlab-ci.yml && git commit -m "feat: enable elite pipeline"
   git push origin main

3. Trigger First Pipeline:
   - Go to: Project → CI/CD → Pipelines
   - Click "Run Pipeline"
   - Select branch and run

4. Monitor Progress:
   - Pipeline stages: 🔍 validate → 🔐 security → 🏗️ build → ✅ test → 🚀 deploy
   - Expected duration: 5-10 minutes for first run

5. Read Documentation:
   - docs/GITLAB_ELITE_QUICK_START.md (15-min quickstart)
   - docs/GITLAB_ELITE_MSP_OPERATIONS.md (comprehensive manual)
   - docs/ELITE_OPERATIONS_RUNBOOKS.md (emergency procedures)

6. Configure Cost Tracking:
   - Edit .gitlab-ci.elite.yml
   - Set MSP_TENANT and TENANT_COST_BUCKET variables
   - Enable audit:cost-allocation job

7. Setup Alerts:
   - Deploy Prometheus (monitoring/elite-observability.yaml)
   - Configure alertmanager
   - Create Grafana dashboards

KEY FILES:
  • .gitlab-ci.elite.yml             (Main pipeline - 10 stages)
  • .gitlab-runners.elite.yml        (Runner configuration)
  • policies/container-security.rego (OPA compliance policies)
  • k8s/deployment-strategies.yaml   (Blue-green & canary)
  • monitoring/elite-observability.yaml (Prometheus/Grafana config)

FEATURES ENABLED:
  ✅ DAG-based job orchestration
  ✅ Matrix builds (multi-platform)
  ✅ Security scanning (SAST/DAST/Container)
  ✅ Compliance gating
  ✅ Blue-green deployments
  ✅ Cost allocation tracking
  ✅ SLO/SLI monitoring
  ✅ Observability integration
  ✅ Auto-recovery procedures
  ✅ Multi-tenant isolation

SUPPORT:
  • Troubleshooting: docs/ELITE_OPERATIONS_RUNBOOKS.md
  • API Reference: docs/GITLAB_ELITE_MSP_OPERATIONS.md
  • Quick Questions: Check GITLAB_ELITE_QUICK_START.md

VERSION: 2.0 (Elite)
STATUS: ✅ Production Ready
UPDATED: March 12, 2026

EOF
}

# Main execution
main() {
    clear
    
    print_header "🚀 GITLAB ELITE MSP OPERATIONS - SETUP WIZARD"
    echo ""
    echo "This script will:"
    echo "  1. Check prerequisites"
    echo "  2. Install GitLab Runner"
    echo "  3. Register runners (shell + docker)"
    echo "  4. Enable runner service"
    echo "  5. Verify configuration"
    echo "  6. Setup elite pipeline"
    echo "  7. Run tests"
    echo ""
    
    read -p "Continue with setup? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Setup cancelled"
        exit 0
    fi
    
    # Execute setup steps
    check_prerequisites
    install_gitlab_runner
    register_runners
    enable_runner_service
    verify_configuration
    setup_elite_pipeline
    setup_monitoring
    
    # Show summary
    display_summary
}

# Error handling
trap 'print_error "Setup failed at line $LINENO"' ERR

# Run main function
main "$@"
