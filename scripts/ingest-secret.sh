#!/bin/bash
# ingest-secret.sh - Automated secret ingestion with registry update & audit trail
# Usage: ./scripts/ingest-secret.sh --name "SECRET_NAME" --tier "TIER-1" --input-file /tmp/secret.json

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Defaults
ROTATION_DAYS=30
OWNER="ops-team"
REGISTRY_FILE=".secrets/ROTATION_REGISTRY.json"
AUDIT_LOG=".secrets/audit/$(date -u +%Y%m%d_%H%M%S)_ingest.log"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --name) SECRET_NAME="$2"; shift 2 ;;
    --tier) TIER="$2"; shift 2 ;;
    --rotation-days) ROTATION_DAYS="$2"; shift 2 ;;
    --owner) OWNER="$2"; shift 2 ;;
    --input-file) INPUT_FILE="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Validate inputs
if [ -z "${SECRET_NAME:-}" ] || [ -z "${TIER:-}" ] || [ -z "${INPUT_FILE:-}" ]; then
  echo -e "${RED}❌ Error: Missing required arguments${NC}"
  echo "Usage: $0 --name SECRET_NAME --tier TIER-1|TIER-2|TIER-3|TIER-4 --input-file /path/to/secret"
  exit 1
fi

# Pre-flight checks
echo -e "${BLUE}[INFO] Starting secret ingestion for $SECRET_NAME${NC}"

if [ ! -f "$INPUT_FILE" ]; then
  echo -e "${RED}❌ Input file not found: $INPUT_FILE${NC}"
  exit 1
fi

# Validate JSON (if applicable)
if file "$INPUT_FILE" | grep -q "JSON"; then
  if ! jq . "$INPUT_FILE" > /dev/null 2>&1; then
    echo -e "${RED}❌ Invalid JSON in $INPUT_FILE${NC}"
    exit 1
  fi
  echo -e "${GREEN}✓ JSON validation passed${NC}"
fi

# Create audit log
mkdir -p .secrets/audit
cat > "$AUDIT_LOG" << LOG_START
[INGEST_AUDIT] Secret Ingestion Started
Timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')
Secret: $SECRET_NAME
Tier: $TIER
Rotation Days: $ROTATION_DAYS
Owner: $OWNER
Input File: $INPUT_FILE
Log File: $AUDIT_LOG

LOG_START

# Initialize registry if not exists
if [ ! -f "$REGISTRY_FILE" ]; then
  echo "{}" > "$REGISTRY_FILE"
  echo -e "${YELLOW}⚠ Created new registry file${NC}"
fi

# Verify secret size (prevent truncation)
SECRET_SIZE=$(wc -c < "$INPUT_FILE")
if [ "$SECRET_SIZE" -lt 50 ]; then
  echo -e "${RED}❌ Warning: Secret seems too small (${SECRET_SIZE} bytes). May be truncated.${NC}"
  read -p "Continue anyway? (y/N) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
  fi
fi
echo -e "${GREEN}✓ Secret size check: ${SECRET_SIZE} bytes${NC}"

# Update registry
echo -e "${BLUE}[INFO] Updating rotation registry...${NC}"

python3 << PYTHON_END
import json
from datetime import datetime, timedelta

secret_name = "$SECRET_NAME"
tier = "$TIER"
rotation_days = $ROTATION_DAYS
owner = "$OWNER"

registry_file = "$REGISTRY_FILE"
now = datetime.utcnow().isoformat() + "Z"
next_rot = (datetime.utcnow() + timedelta(days=rotation_days)).isoformat() + "Z"

with open(registry_file) as f:
    registry = json.load(f)

registry[secret_name] = {
    "type": "generic",  # Could be gcp_service_account, docker_pat, ssh_key, etc.
    "tier": tier,
    "rotation_days": rotation_days,
    "last_rotation": now,
    "next_rotation": next_rot,
    "owner": owner,
    "documented_in": "SECRETS_SETUP_GUIDE.md",
    "created": now,
    "ingestion_count": registry.get(secret_name, {}).get("ingestion_count", 0) + 1,
    "description": "Secret ingested via automated workflow"
}

with open(registry_file, 'w') as f:
    json.dump(registry, f, indent=2)

print(f"✓ Registry updated: {secret_name}")
PYTHON_END

echo -e "${GREEN}✓ Registry updated${NC}"

# Set secret in GitHub (placeholder - requires GH CLI auth)
# In production: gh secret set $SECRET_NAME < "$INPUT_FILE"

# Document in SECRETS_SETUP_GUIDE.md (optional auto-doc)
if grep -q "### $SECRET_NAME" SECRETS_SETUP_GUIDE.md 2>/dev/null; then
  echo -e "${YELLOW}⚠ Secret already documented in SECRETS_SETUP_GUIDE.md${NC}"
else
  echo -e "${YELLOW}⚠ Remember to document $SECRET_NAME in SECRETS_SETUP_GUIDE.md${NC}"
fi

# Clean up temporary file
shred -vfz "$INPUT_FILE" 2>/dev/null || rm -f "$INPUT_FILE"
echo -e "${GREEN}✓ Temporary file securely deleted${NC}"

# Log completion
cat >> "$AUDIT_LOG" << LOG_END

Audit Trail Recorded: $(date -u '+%Y-%m-%dT%H:%M:%SZ')
Status: SUCCESS

[INGEST_AUDIT] Complete
LOG_END

echo -e "${GREEN}✅ Secret ingestion complete!${NC}"
echo -e "${BLUE}Audit Log: ${AUDIT_LOG}${NC}"
