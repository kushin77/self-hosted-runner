#!/bin/bash
set -euo pipefail
AUDIT_DIR="${AUDIT_DIR:-logs/multi-cloud-audit}"
mkdir -p "$AUDIT_DIR"
log(){ echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"action\":\"$1\",\"status\":\"$2\",\"details\":\"$3\"}" >> "$AUDIT_DIR/aws-oidc-migration-verify-$(date +%Y%m%d-%H%M%S).jsonl"; }

if aws sts get-caller-identity >/dev/null 2>&1; then
  log "verify_primary" "success" "AWS primary OK"
else
  log "verify_primary" "failed" "AWS primary failed"
fi
if [[ -f scripts/core/credential-helper.sh ]]; then
  log "verify_helper" "success" "Credential helper present"
else
  log "verify_helper" "failed" "Credential helper missing"
fi
log "verify_complete" "success" "Verification run complete"
echo "VERIFY COMPLETE"
