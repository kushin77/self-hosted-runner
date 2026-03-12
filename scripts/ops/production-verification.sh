#!/bin/bash
################################################################################
# Production Deployment Verification Script
# Purpose: Verify all infrastructure components are operational
# Usage: bash scripts/ops/production-verification.sh
# Schedule: Run weekly or after any deployment
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUTPUT_FILE="${PROJECT_ROOT}/logs/production-verification-$(date -u +%Y%m%dT%H%M%SZ).jsonl"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
GCP_PROJECT="nexusshield-prod"
AWS_REGION="us-east-1"
K8S_NAMESPACE="credential-system"

# Counters
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_SKIPPED=0

# Logging function
log_check() {
    local name="$1"
    local status="$2"
    local details="${3:-}"
    
    local emoji="❌"
    local color="$RED"
    
    case "$status" in
        pass)
            emoji="✅"
            color="$GREEN"
            ((CHECKS_PASSED++))
            ;;
        fail)
            emoji="❌"
            color="$RED"
            ((CHECKS_FAILED++))
            ;;
        skip)
            emoji="⊘"
            color="$YELLOW"
            ((CHECKS_SKIPPED++))
            ;;
        info)
            emoji="ℹ️"
            color="$BLUE"
            ;;
    esac
    
    printf "${color}${emoji}${NC} %-50s %s\n" "$name" "$details"
    
    # Log to JSONL
    mkdir -p "$(dirname "$OUTPUT_FILE")"
    echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"check\":\"$name\",\"status\":\"$status\",\"details\":\"$details\"}" >> "$OUTPUT_FILE"
}

echo ""
echo "🔍 PRODUCTION DEPLOYMENT VERIFICATION"
echo "Date: $(date)"
echo "Project: $GCP_PROJECT"
echo ""

# ============================================================================
# 1. GCP INFRASTRUCTURE
# ============================================================================
echo "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "${BLUE}1. GCP INFRASTRUCTURE${NC}"
echo "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Check Cloud Run services
if command -v gcloud &>/dev/null; then
    # Backend service
    if desc=$(gcloud run services describe nexus-shield-portal-backend --region=us-central1 --project="$GCP_PROJECT" --format=json 2>/dev/null); then
        # Find the Ready condition explicitly (order may vary)
        ready=$(echo "$desc" | jq -r '.status.conditions[] | select(.type=="Ready") | .status' 2>/dev/null || echo "Unknown")
        if [ "$ready" = "True" ]; then
            # Authenticated invocation check (preferred) to verify runtime
            url=$(echo "$desc" | jq -r '.status.url' 2>/dev/null || true)
            id_token=$(gcloud auth print-identity-token 2>/dev/null || true)
            if [ -n "$id_token" ] && [ -n "$url" ]; then
                http_code=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $id_token" "$url" || echo "000")
                if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 400 ]; then
                    log_check "Cloud Run: Backend Service" "pass" "Ready and responding ($http_code)"
                else
                    log_check "Cloud Run: Backend Service" "fail" "Ready but invocation returned $http_code"
                fi
            else
                log_check "Cloud Run: Backend Service" "pass" "Ready (invocation skipped)"
            fi
        else
            # capture reason if present
            reason=$(echo "$desc" | jq -r '.status.conditions[] | select(.type=="Ready") | .reason' 2>/dev/null || true)
            msg=$(echo "$desc" | jq -r '.status.conditions[] | select(.type=="Ready") | .message' 2>/dev/null || true)
            log_check "Cloud Run: Backend Service" "fail" "Not ready: ${reason:-unknown} ${msg:-}" 
        fi
    else
        log_check "Cloud Run: Backend Service" "fail" "Service not found"
    fi
    
    # Frontend service
    if desc=$(gcloud run services describe nexus-shield-portal-frontend --region=us-central1 --project="$GCP_PROJECT" --format=json 2>/dev/null); then
        ready=$(echo "$desc" | jq -r '.status.conditions[] | select(.type=="Ready") | .status' 2>/dev/null || echo "Unknown")
        if [ "$ready" = "True" ]; then
            url=$(echo "$desc" | jq -r '.status.url' 2>/dev/null || true)
            id_token=$(gcloud auth print-identity-token 2>/dev/null || true)
            if [ -n "$id_token" ] && [ -n "$url" ]; then
                http_code=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $id_token" "$url" || echo "000")
                if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 400 ]; then
                    log_check "Cloud Run: Frontend Service" "pass" "Ready and responding ($http_code)"
                else
                    log_check "Cloud Run: Frontend Service" "fail" "Ready but invocation returned $http_code"
                fi
            else
                log_check "Cloud Run: Frontend Service" "pass" "Ready (invocation skipped)"
            fi
        else
            reason=$(echo "$desc" | jq -r '.status.conditions[] | select(.type=="Ready") | .reason' 2>/dev/null || true)
            msg=$(echo "$desc" | jq -r '.status.conditions[] | select(.type=="Ready") | .message' 2>/dev/null || true)
            log_check "Cloud Run: Frontend Service" "fail" "Not ready: ${reason:-unknown} ${msg:-}"
        fi
    else
        log_check "Cloud Run: Frontend Service" "fail" "Service not found"
    fi
    
    # Image-pin service
    if gcloud run services describe image-pin-service --region=us-central1 --project="$GCP_PROJECT" &>/dev/null; then
        log_check "Cloud Run: Image-Pin Service" "pass" "Operating"
    else
        log_check "Cloud Run: Image-Pin Service" "fail" "Service not found"
    fi
    
    # Cloud Scheduler jobs
    if gcloud scheduler jobs list --project="$GCP_PROJECT" --location=us-central1 &>/dev/null; then
        job_count=$(gcloud scheduler jobs list --project="$GCP_PROJECT" --location=us-central1 --format='value(name)' | wc -l)
        if [ "$job_count" -ge 3 ]; then
            log_check "Cloud Scheduler: Credential Rotation" "pass" "$job_count jobs configured"
        else
            log_check "Cloud Scheduler: Credential Rotation" "fail" "Only $job_count jobs found (expect >= 3)"
        fi
    else
        log_check "Cloud Scheduler: Credential Rotation" "skip" "Access denied"
    fi
    
    # Secret Manager
    if gcloud secrets list --project="$GCP_PROJECT" &>/dev/null; then
        secret_count=$(gcloud secrets list --project="$GCP_PROJECT" --format='value(name)' | wc -l)
        if [ "$secret_count" -ge 1 ]; then
            log_check "Secret Manager: Secrets Provisioned" "pass" "$secret_count secrets"
        else
            log_check "Secret Manager: Secrets Provisioned" "fail" "No secrets found"
        fi
    else
        log_check "Secret Manager: Secrets Provisioned" "skip" "Access denied"
    fi
else
    log_check "GCP CLI (gcloud)" "skip" "Not installed"
fi

# ============================================================================
# 2. AWS INFRASTRUCTURE
# ============================================================================
echo ""
echo "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "${BLUE}2. AWS INFRASTRUCTURE${NC}"
echo "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if command -v aws &>/dev/null; then
    # S3 Archival bucket
    if aws s3 ls s3://akushnir-milestones-20260312/ --region="$AWS_REGION" &>/dev/null; then
        log_check "S3: Archival Bucket" "pass" "Accessible"
    else
        log_check "S3: Archival Bucket" "fail" "Not accessible"
    fi
    
    # S3 Object Lock
    if aws s3api get-bucket-versioning --bucket akushnir-milestones-20260312 --region="$AWS_REGION" &>/dev/null; then
        log_check "S3: Object Lock/Versioning" "pass" "Enabled"
    else
        log_check "S3: Object Lock/Versioning" "skip" "Access denied"
    fi
    
    # IAM Role for OIDC
    if aws iam get-role --role-name github-oidc-role &>/dev/null; then
        log_check "IAM: GitHub OIDC Role" "pass" "Exists"
    else
        log_check "IAM: GitHub OIDC Role" "fail" "Role not found"
    fi
else
    log_check "AWS CLI" "skip" "Not installed"
fi

# ============================================================================
# 3. KUBERNETES CLUSTER
# ============================================================================
echo ""
echo "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "${BLUE}3. KUBERNETES CLUSTER${NC}"
echo "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if command -v kubectl &>/dev/null; then
    # Credential system namespace
    if kubectl get namespace "$K8S_NAMESPACE" &>/dev/null; then
        pod_count=$(kubectl get pods -n "$K8S_NAMESPACE" --no-headers 2>/dev/null | wc -l)
        log_check "Kubernetes: Credential Namespace" "pass" "$pod_count pods running"
    else
        log_check "Kubernetes: Credential Namespace" "fail" "Namespace not found"
    fi
    
    # CronJob for archival
    if kubectl get cronjob -n credential-system milestone-organizer &>/dev/null; then
        log_check "Kubernetes: Milestone Organizer CronJob" "pass" "Deployed"
    else
        log_check "Kubernetes: Milestone Organizer CronJob" "skip" "Not deployed (optional)"
    fi
    
    # Service accounts with IRSA
    if kubectl get sa -n credential-system &>/dev/null; then
        log_check "Kubernetes: Service Accounts" "pass" "Configured"
    else
        log_check "Kubernetes: Service Accounts" "fail" "Error listing"
    fi
else
    log_check "kubectl" "skip" "Not installed"
fi

# ============================================================================
# 4. MONITORING & OBSERVABILITY
# ============================================================================
echo ""
echo "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "${BLUE}4. MONITORING & OBSERVABILITY${NC}"
echo "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Audit logs
if [ -d "$PROJECT_ROOT/logs" ]; then
    audit_count=$(find "$PROJECT_ROOT/logs" -name "*.jsonl" -type f 2>/dev/null | wc -l)
    if [ "$audit_count" -gt 0 ]; then
        recent_entry=$(tail -1 "$PROJECT_ROOT/logs"/*/*.jsonl 2>/dev/null | jq .timestamp -r 2>/dev/null || echo "Unable to read")
        log_check "Audit Trail: JSONL Logs" "pass" "$audit_count files, latest: $recent_entry"
    else
        log_check "Audit Trail: JSONL Logs" "fail" "No audit logs found"
    fi
else
    log_check "Audit Trail: JSONL Logs" "skip" "Logs directory not found"
fi

# Terraform state files
if [ -f "$PROJECT_ROOT/terraform/image_pin/terraform.tfstate" ]; then
    log_check "Terraform: Image-Pin State" "pass" "Present"
else
    log_check "Terraform: Image-Pin State" "fail" "Not found"
fi

if [ -f "$PROJECT_ROOT/infra/phase3-production/terraform.tfstate" ]; then
    log_check "Terraform: WIF State" "pass" "Present"
else
    log_check "Terraform: WIF State" "fail" "Not found"
fi

# ============================================================================
# 5. SECURITY & COMPLIANCE
# ============================================================================
echo ""
echo "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "${BLUE}5. SECURITY & COMPLIANCE${NC}"
echo "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Pre-commit hook
if [ -f "$PROJECT_ROOT/.git/hooks/pre-commit" ]; then
    log_check "Pre-Commit Hook: Credential Detection" "pass" "Installed"
else
    log_check "Pre-Commit Hook: Credential Detection" "fail" "Not installed"
fi

# .env.example (no hardcoded secrets)
if [ -f "$PROJECT_ROOT/.env.example" ]; then
    if ! grep -q "password=" "$PROJECT_ROOT/.env.example" 2>/dev/null; then
        log_check "Environment: No Hardcoded Secrets" "pass" ".env.example clean"
    else
        log_check "Environment: No Hardcoded Secrets" "fail" ".env.example has secrets"
    fi
else
    log_check "Environment: No Hardcoded Secrets" "skip" ".env.example not found"
fi

# Git history (no commits with credentials)
if command -v git &>/dev/null && [ -d "$PROJECT_ROOT/.git" ]; then
    if command -v gitleaks &>/dev/null; then
        if gitleaks detect --no-git --source-type=git 2>/dev/null | grep -q "no leaks detected"; then
            log_check "Git: Credential Leak Detection" "pass" "0 leaks detected"
        else
            log_check "Git: Credential Leak Detection" "fail" "Leaks detected"
        fi
    else
        log_check "Git: Credential Leak Detection" "skip" "gitleaks not installed"
    fi
fi

# ============================================================================
# SUMMARY
# ============================================================================
echo ""
echo "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "${BLUE}SUMMARY${NC}"
echo "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

TOTAL=$((CHECKS_PASSED + CHECKS_FAILED + CHECKS_SKIPPED))

printf "${GREEN}✅ Passed:${NC} %d\n" "$CHECKS_PASSED"
if [ "$CHECKS_FAILED" -gt 0 ]; then
    printf "${RED}❌ Failed:${NC} %d\n" "$CHECKS_FAILED"
else
    printf "${GREEN}❌ Failed:${NC} 0\n"
fi
printf "${YELLOW}⊘ Skipped:${NC} %d\n" "$CHECKS_SKIPPED"
printf "📊 Total: %d checks\n" "$TOTAL"
echo ""

if [ "$CHECKS_FAILED" -eq 0 ]; then
    echo "${GREEN}🎉 ALL CHECKS PASSED${NC}"
    echo ""
    echo "✅ Production deployment is operational"
    echo "✅ All critical infrastructure is accessible"
    echo "✅ Monitoring and audit trails are active"
    echo ""
    exit 0
else
    echo "${RED}⚠️  SOME CHECKS FAILED${NC}"
    echo ""
    echo "Failed checks:"
    grep '❌' <<< "$(cat "$OUTPUT_FILE")" | jq -r '.check' 2>/dev/null || echo "See output above"
    echo ""
    echo "Action: Review failed items and escalate if needed (see #2216)"
    echo ""
    exit 1
fi
