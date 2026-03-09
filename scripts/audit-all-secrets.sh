#!/bin/bash
set -euo pipefail

##############################################################################
# Comprehensive Secrets Audit Script
# Purpose: Discover ALL secrets across repo, org, and workflows
# Output: Immutable inventory JSON + classification + migration plan
##############################################################################

REPO="${REPO:-kushin77/self-hosted-runner}"
ORG="${ORG:-kushin77}"
TIMESTAMP=$(date -u +'%Y-%m-%d_%H:%M:%S_UTC')
OUTPUT_DIR="secrets-inventory"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $(date '+%H:%M:%S') $1"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $(date '+%H:%M:%S') $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $(date '+%H:%M:%S') $1"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $(date '+%H:%M:%S') $1"; }

mkdir -p "$OUTPUT_DIR"

##############################################################################
# PHASE 1: Repository Level Secrets
##############################################################################

log_info "Phase 1: Scanning Repository Secrets..."

REPO_SECRETS_FILE="$OUTPUT_DIR/repo-secrets-${TIMESTAMP}.json"
REPO_SECRETS_COUNT=0

{
  echo "{"
  echo '  "scan_type": "repository_secrets",'
  echo '  "repository": "'$REPO'",'
  echo '  "timestamp": "'$TIMESTAMP'",'
  echo '  "secrets": ['

  FIRST=true
  gh secret list --repo "$REPO" --json name,createdAt,updatedAt 2>/dev/null | jq -r '.[] | @json' | while read -r secret_json; do
    if [ "$FIRST" = false ]; then
      echo ","
    fi
    FIRST=false
    
    SECRET_NAME=$(echo "$secret_json" | jq -r '.name')
    CREATED=$(echo "$secret_json" | jq -r '.createdAt')
    UPDATED=$(echo "$secret_json" | jq -r '.updatedAt')
    
    echo -n "    {"
    echo -n "\"name\": \"$SECRET_NAME\", "
    echo -n "\"created_at\": \"$CREATED\", "
    echo -n "\"updated_at\": \"$UPDATED\", "
    
    # Classify the secret
    if [[ "$SECRET_NAME" =~ ^AWS_|_AWS$|AWS_ ]]; then
      echo -n "\"type\": \"aws_credential\", \"lifetime\": \"permanent\", \"risk\": \"high\", "
    elif [[ "$SECRET_NAME" =~ ^TERRAFORM_|_TERRAFORM$|TERRAFORM_ ]]; then
      echo -n "\"type\": \"infrastructure_credential\", \"lifetime\": \"permanent\", \"risk\": \"high\", "
    elif [[ "$SECRET_NAME" =~ ^GCP_|_GCP$|GCP_ ]]; then
      echo -n "\"type\": \"gcp_credential\", \"lifetime\": \"permanent\", \"risk\": \"high\", "
    elif [[ "$SECRET_NAME" =~ ^VAULT_|_VAULT$|VAULT_ ]]; then
      echo -n "\"type\": \"vault_credential\", \"lifetime\": \"permanent\", \"risk\": \"high\", "
    elif [[ "$SECRET_NAME" =~ ^API_|_API$|API_|_TOKEN$|TOKEN_|_KEY$|KEY_ ]]; then
      echo -n "\"type\": \"api_token\", \"lifetime\": \"permanent\", \"risk\": \"high\", "
    elif [[ "$SECRET_NAME" =~ ^SSH_|_SSH$|SSH_|DEPLOY_KEY ]]; then
      echo -n "\"type\": \"ssh_key\", \"lifetime\": \"permanent\", \"risk\": \"critical\", "
    elif [[ "$SECRET_NAME" =~ ^DB_|DATABASE_|_DB$|_PASSWORD ]]; then
      echo -n "\"type\": \"database_credential\", \"lifetime\": \"permanent\", \"risk\": \"critical\", "
    elif [[ "$SECRET_NAME" =~ ^SLACK_|WEBHOOK_|DISCORD_ ]]; then
      echo -n "\"type\": \"webhook_secret\", \"lifetime\": \"permanent\", \"risk\": \"medium\", "
    else
      echo -n "\"type\": \"unknown\", \"lifetime\": \"unknown\", \"risk\": \"medium\", "
    fi
    
    echo -n "\"status\": \"requires_migration\", "
    echo -n "\"target_store\": \"GSM\""
    echo -n "}"
    
    ((REPO_SECRETS_COUNT++))
  done

  echo ""
  echo "  ]"
  echo "}"
} | tee "$REPO_SECRETS_FILE"

log_pass "Found $REPO_SECRETS_COUNT repository secrets"

##############################################################################
# PHASE 2: Organization Level Secrets
##############################################################################

log_info "Phase 2: Scanning Organization Secrets..."

ORG_SECRETS_FILE="$OUTPUT_DIR/org-secrets-${TIMESTAMP}.json"
ORG_SECRETS_COUNT=0

{
  echo "{"
  echo '  "scan_type": "organization_secrets",'
  echo '  "organization": "'$ORG'",'
  echo '  "timestamp": "'$TIMESTAMP'",'
  echo '  "secrets": ['

  FIRST=true
  gh secret list --org "$ORG" --json name,createdAt,updatedAt 2>/dev/null | jq -r '.[] | @json' | while read -r secret_json; do
    if [ "$FIRST" = false ]; then
      echo ","
    fi
    FIRST=false
    
    SECRET_NAME=$(echo "$secret_json" | jq -r '.name')
    CREATED=$(echo "$secret_json" | jq -r '.createdAt')
    UPDATED=$(echo "$secret_json" | jq -r '.updatedAt')
    
    echo -n "    {"
    echo -n "\"name\": \"$SECRET_NAME\", "
    echo -n "\"scope\": \"organization\", "
    echo -n "\"created_at\": \"$CREATED\", "
    echo -n "\"updated_at\": \"$UPDATED\", "
    echo -n "\"target_store\": \"GSM\""
    echo -n "}"
    
    ((ORG_SECRETS_COUNT++))
  done

  echo ""
  echo "  ]"
  echo "}"
} | tee "$ORG_SECRETS_FILE"

log_pass "Found $ORG_SECRETS_COUNT organization secrets"

##############################################################################
# PHASE 3: Workflow File Analysis
##############################################################################

log_info "Phase 3: Scanning Workflow Files..."

WORKFLOW_SECRETS_FILE="$OUTPUT_DIR/workflow-secrets-${TIMESTAMP}.json"
WORKFLOW_PATTERNS_FOUND=0

{
  echo "{"
  echo '  "scan_type": "workflow_embedded_secrets",'
  echo '  "scan_dir": ".github/workflows",'
  echo '  "timestamp": "'$TIMESTAMP'",'
  echo '  "patterns_found": ['

  FIRST=true
  
  # Look for known secret patterns in workflow files
  for wf_file in .github/workflows/*.yml .github/workflows/*.yaml 2>/dev/null || true; do
    if [ ! -f "$wf_file" ]; then
      continue
    fi
    
    # Pattern: secrets.SOMETHING_NAME
    while IFS= read -r line; do
      if [[ $line =~ secrets\.([A-Z_]+) ]]; then
        if [ "$FIRST" = false ]; then
          echo ","
        fi
        FIRST=false
        
        SECRET_NAME="${BASH_REMATCH[1]}"
        echo -n "    {"
        echo -n "\"file\": \"$(basename "$wf_file")\", "
        echo -n "\"secret_ref\": \"secrets.$SECRET_NAME\", "
        echo -n "\"risk\": \"high\", "
        echo -n "\"action\": \"remove_and_use_dynamic_retrieval\""
        echo -n "}"
        
        ((WORKFLOW_PATTERNS_FOUND++))
      fi
    done < "$wf_file"
  done

  echo ""
  echo "  ]"
  echo "}"
} | tee "$WORKFLOW_SECRETS_FILE"

log_pass "Found $WORKFLOW_PATTERNS_FOUND embedded secret patterns in workflows"

##############################################################################
# PHASE 4: Script Analysis
##############################################################################

log_info "Phase 4: Scanning Scripts for Hardcoded Secrets..."

SCRIPT_SECRETS_FILE="$OUTPUT_DIR/script-secrets-${TIMESTAMP}.json"
SCRIPT_PATTERNS_FOUND=0

{
  echo "{"
  echo '  "scan_type": "script_hardcoded_secrets",'
  echo '  "scan_dirs": ["scripts", "ci", "deploy", "bootstrap"],'
  echo '  "timestamp": "'$TIMESTAMP'",'
  echo '  "patterns_found": ['

  FIRST=true
  
  # Look for export/assignment patterns that might contain secrets
  for script in scripts/**/*.sh ci/**/*.sh deploy/**/*.sh bootstrap/**/*.sh 2>/dev/null || true; do
    if [ ! -f "$script" ]; then
      continue
    fi
    
    # Pattern: export VAR=value or VAR=value (for sensitive names)
    while IFS= read -r line; do
      if [[ $line =~ (export\s+)?(AWS_SECRET|DB_PASSWORD|API_KEY|TOKEN|SECRET_KEY|PRIVATE_KEY|SSH_KEY)=.* ]]; then
        if [ "$FIRST" = false ]; then
          echo ","
        fi
        FIRST=false
        
        echo -n "    {"
        echo -n "\"file\": \"$(basename "$script")\", "
        echo -n "\"line\": \"${line:0:80}...\", "
        echo -n "\"risk\": \"critical\", "
        echo -n "\"action\": \"extract_to_GSM_and_remove\""
        echo -n "}"
        
        ((SCRIPT_PATTERNS_FOUND++))
      fi
    done < "$script"
  done

  echo ""
  echo "  ]"
  echo "}"
} | tee "$SCRIPT_SECRETS_FILE"

log_pass "Found $SCRIPT_PATTERNS_FOUND hardcoded patterns in scripts"

##############################################################################
# PHASE 5: Generate Comprehensive Inventory
##############################################################################

log_info "Phase 5: Generating Comprehensive Inventory..."

INVENTORY_FILE="$OUTPUT_DIR/secrets-inventory-complete-${TIMESTAMP}.json"

{
  echo "{"
  echo '  "audit_timestamp": "'$TIMESTAMP'",'
  echo '  "repository": "'$REPO'",'
  echo '  "organization": "'$ORG'",'
  echo '  "summary": {'
  echo '    "repository_secrets_count": '$REPO_SECRETS_COUNT','
  echo '    "organization_secrets_count": '$ORG_SECRETS_COUNT','
  echo '    "workflow_patterns_found": '$WORKFLOW_PATTERNS_FOUND','
  echo '    "script_patterns_found": '$SCRIPT_PATTERNS_FOUND','
  echo '    "total_secrets": '$(($REPO_SECRETS_COUNT + $ORG_SECRETS_COUNT + $WORKFLOW_PATTERNS_FOUND + $SCRIPT_PATTERNS_FOUND))',' 
  echo '    "migration_status": "pending"'
  echo '  },'
  echo '  "classification": {'
  echo '    "critical_risk": ['
  echo '      "SSH_* keys",'
  echo '      "DB_* credentials",'
  echo '      "Terraform backend passwords"'
  echo '    ],'
  echo '    "high_risk": ['
  echo '      "AWS_* credentials",'
  echo '      "API_* tokens",'
  echo '      "GCP_* credentials"'
  echo '    ],'
  echo '    "medium_risk": ['
  echo '      "Webhook secrets",'
  echo '      "Integration tokens"'
  echo '    ]'
  echo '  },'
  echo '  "migration_plan": {'
  echo '    "phase_1_critical": "Terraform, SSH, DB credentials",
  echo '    "phase_2_high": "AWS, GCP, API keys",
  echo '    "phase_3_medium": "Webhooks, Slack tokens",
  echo '    "timeline": "3 hours total",'
  echo '    "rollback_available": true'
  echo '  },'
  echo '  "source_files": ['
  echo '    "'$REPO_SECRETS_FILE'",'
  echo '    "'$ORG_SECRETS_FILE'",'
  echo '    "'$WORKFLOW_SECRETS_FILE'",'
  echo '    "'$SCRIPT_SECRETS_FILE'"'
  echo '  ]'
  echo "}"
} | tee "$INVENTORY_FILE"

log_pass "Comprehensive inventory generated: $INVENTORY_FILE"

##############################################################################
# SUMMARY
##############################################################################

echo ""
echo -e "${BLUE}======================================================${NC}"
echo -e "${BLUE}SECRETS AUDIT COMPLETE${NC}"
echo -e "${BLUE}======================================================${NC}"
echo -e "Timestamp: $TIMESTAMP"
echo -e "Repository: $REPO"
echo -e "Organization: $ORG"
echo ""
echo -e "Summary:"
echo -e "  ${GREEN}Repository Secrets:${NC} $REPO_SECRETS_COUNT"
echo -e "  ${GREEN}Organization Secrets:${NC} $ORG_SECRETS_COUNT"
echo -e "  ${YELLOW}Workflow Patterns:${NC} $WORKFLOW_PATTERNS_FOUND"
echo -e "  ${YELLOW}Script Patterns:${NC} $SCRIPT_PATTERNS_FOUND"
echo -e "  ${RED}Total Credentials to Migrate:${NC} $(($REPO_SECRETS_COUNT + $ORG_SECRETS_COUNT + $WORKFLOW_PATTERNS_FOUND + $SCRIPT_PATTERNS_FOUND))"
echo ""
echo -e "Output Files:"
echo -e "  • $REPO_SECRETS_FILE"
echo -e "  • $ORG_SECRETS_FILE"
echo -e "  • $WORKFLOW_SECRETS_FILE"
echo -e "  • $SCRIPT_SECRETS_FILE"
echo -e "  • $INVENTORY_FILE (MAIN)"
echo ""
echo -e "Next Steps:"
echo -e "  1. Review: $INVENTORY_FILE"
echo -e "  2. Plan: Migration phases by risk level"
echo -e "  3. Execute: scripts/migrate-secrets-to-gsm.sh"
echo ""
echo -e "${BLUE}======================================================${NC}"
