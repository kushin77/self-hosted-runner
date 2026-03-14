#!/bin/bash
# ENFORCEMENT: Check prerequisites
# Ensures all tools and access are available before deployment

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_commands() {
    local failed=0
    
    echo "📋 Checking required commands..."
    
    local commands=("git" "ssh" "ssh-keygen" "gcloud" "bash" "jq" "curl")
    
    for cmd in "${commands[@]}"; do
        if command -v "$cmd" &>/dev/null; then
            printf "  ${GREEN}✓${NC} Found: $cmd\n"
        else
            printf "  ${RED}✗${NC} Missing: $cmd\n"
            echo "     Fix: Install $cmd or add to PATH"
            failed=1
        fi
    done
    
    return $((failed > 0 ? 1 : 0))
}

check_directory_structure() {
    local failed=0
    
    echo ""
    echo "📂 Checking directory structure..."
    
    local required_dirs=(
        "logs"
        "secrets/ssh"
        ".credential-state"
        "scripts/ssh_service_accounts"
        "scripts/enforce"
    )
    
    for dir in "${required_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            printf "  ${GREEN}✓${NC} Directory exists: $dir\n"
        else
            printf "  ${RED}✗${NC} Missing directory: $dir\n"
            echo "     Fix: mkdir -p $dir"
            failed=1
        fi
    done
    
    return $((failed > 0 ? 1 : 0))
}

check_git_config() {
    local failed=0
    
    echo ""
    echo "🔐 Checking git configuration..."
    
    if git config user.email &>/dev/null; then
        local email=$(git config user.email)
        printf "  ${GREEN}✓${NC} Git user email: $email\n"
    else
        printf "  ${RED}✗${NC} Git user email not configured\n"
        echo "     Fix: git config --global user.email 'your@email.com'"
        failed=1
    fi
    
    if git config user.name &>/dev/null; then
        local name=$(git config user.name)
        printf "  ${GREEN}✓${NC} Git user name: $name\n"
    else
        printf "  ${RED}✗${NC} Git user name not configured\n"
        echo "     Fix: git config --global user.name 'Your Name'"
        failed=1
    fi
    
    return $((failed > 0 ? 1 : 0))
}

check_ssh_keys() {
    local failed=0
    
    echo ""
    echo "🔑 Checking SSH configuration..."
    
    if [[ -f ~/.ssh/id_ed25519 ]]; then
        local perms=$(stat -c %a ~/.ssh/id_ed25519 2>/dev/null || stat -f %OLp ~/.ssh/id_ed25519)
        if [[ "$perms" == "600" ]]; then
            printf "  ${GREEN}✓${NC} SSH key present with correct permissions (600)\n"
        else
            printf "  ${YELLOW}!${NC} SSH key has wrong permissions ($perms, should be 600)\n"
            echo "     Fix: chmod 600 ~/.ssh/id_ed25519"
        fi
    else
        printf "  ${RED}✗${NC} SSH key not found: ~/.ssh/id_ed25519\n"
        echo "     Fix: Generate with ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519"
        failed=1
    fi
    
    return $((failed > 0 ? 1 : 0))
}

check_gcp_auth() {
    local failed=0
    
    echo ""
    echo "☁️  Checking GCP authentication..."
    
    if gcloud auth list 2>/dev/null | grep -q "ACTIVE"; then
        printf "  ${GREEN}✓${NC} GCP authentication active\n"
    else
        printf "  ${RED}✗${NC} GCP not authenticated\n"
        echo "     Fix: gcloud auth application-default login"
        failed=1
    fi
    
    if gcloud config get-value project 2>/dev/null | grep -q "nexusshield"; then
        local project=$(gcloud config get-value project)
        printf "  ${GREEN}✓${NC} GCP project set: $project\n"
    else
        printf "  ${RED}✗${NC} GCP project not set correctly\n"
        echo "     Fix: gcloud config set project nexusshield-prod"
        failed=1
    fi
    
    return $((failed > 0 ? 1 : 0))
}

check_gcp_secrets() {
    local failed=0
    
    echo ""
    echo "🔐 Checking GCP Secret Manager access..."
    
    local secret_count=$(gcloud secrets list --project=nexusshield-prod 2>/dev/null | tail -n +2 | wc -l || echo 0)
    
    if [[ $secret_count -gt 5 ]]; then
        printf "  ${GREEN}✓${NC} GCP Secret Manager accessible ($secret_count secrets found)\n"
    else
        printf "  ${RED}✗${NC} GCP Secret Manager unreachable or empty\n"
        echo "     Fix: Verify GCP authentication and project access"
        failed=1
    fi
    
    return $((failed > 0 ? 1 : 0))
}

check_target_connectivity() {
    local failed=0
    
    echo ""
    echo "🌐 Checking target infrastructure connectivity..."
    
    # Production target
    if ssh -i ~/.ssh/id_ed25519 -o ConnectTimeout=5 ubuntu@192.168.168.42 "echo 'OK'" &>/dev/null 2>&1; then
        printf "  ${GREEN}✓${NC} Production target reachable (192.168.168.42)\n"
    else
        printf "  ${RED}✗${NC} Production target unreachable (192.168.168.42)\n"
        echo "     Fix: Check network connectivity, VPN, SSH key permissions"
        failed=1
    fi
    
    # Backup target
    if ssh -i ~/.ssh/id_ed25519 -o ConnectTimeout=5 ubuntu@192.168.168.39 "echo 'OK'" &>/dev/null 2>&1; then
        printf "  ${GREEN}✓${NC} Backup target reachable (192.168.168.39)\n"
    else
        printf "  ${YELLOW}!${NC} Backup target unreachable (192.168.168.39)\n"
        echo "     Note: Backup is optional, main deployment can proceed"
    fi
    
    return 0
}

main() {
    echo ""
    echo "════════════════════════════════════════════"
    echo "PREREQUISITE CHECK"
    echo "════════════════════════════════════════════"
    echo ""
    
    local all_passed=0
    
    check_commands || all_passed=1
    check_directory_structure || all_passed=1
    check_git_config || all_passed=1
    check_ssh_keys || all_passed=1
    check_gcp_auth || all_passed=1
    check_gcp_secrets || all_passed=1
    check_target_connectivity || all_passed=1
    
    echo ""
    echo "════════════════════════════════════════════"
    
    if [[ $all_passed -eq 0 ]]; then
        printf "\n${GREEN}✅ All prerequisites met - ready for deployment${NC}\n\n"
        exit 0
    else
        printf "\n${RED}❌ Some prerequisites missing - see fixes above${NC}\n\n"
        exit 1
    fi
}

main "$@"
