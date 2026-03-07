#!/usr/bin/env bash
set -euo pipefail

# Verify at least 2 tiers healthy (GCP, AWS, GitHub, Local backup)

HEALTHY=0
log(){ echo "[health] $(date -u +'%Y-%m-%dT%H:%M:%SZ') $*"; }
warn(){ echo "[health] WARN: $*"; }

# Tier 1: GCP
if gcloud secrets versions list runner-mgmt-token --limit=1 >/dev/null 2>&1; then
  log "GCP Secret Manager accessible"
  HEALTHY=$((HEALTHY+1))
else
  warn "GCP Secret Manager unavailable"
fi

# Tier 2: AWS
if aws secretsmanager describe-secret --secret-id runner-mgmt-token >/dev/null 2>&1; then
  log "AWS Secrets Manager accessible"
  HEALTHY=$((HEALTHY+1))
else
  warn "AWS Secrets Manager unavailable or credentials missing"
fi

# Tier 3: GitHub
if gh secret list --repo kushin77/self-hosted-runner | grep -q RUNNER_MGMT_TOKEN; then
  log "GitHub Actions secret RUNNER_MGMT_TOKEN present"
  HEALTHY=$((HEALTHY+1))
else
  warn "GitHub secret RUNNER_MGMT_TOKEN missing"
fi

# Tier 4: Local backup
if [ -f ~/.vault/encrypted-runner-mgmt-token ]; then
  log "Local encrypted backup present"
  HEALTHY=$((HEALTHY+1))
else
  warn "Local backup not present"
fi

log "Healthy tiers: $HEALTHY/4"
if [ $HEALTHY -lt 2 ]; then
  echo "CRITICAL: less than 2 tiers healthy" >&2
  exit 2
fi

log "Health check passed"
exit 0
#!/bin/bash

# Check health and availability of all secret storage tiers
# Usage: ./scripts/check-secret-health.sh

echo "╔════════════════════════════════════════════╗"
echo "║    SECRET STORAGE HEALTH CHECK             ║"
echo "║    $(date +'%Y-%m-%d %H:%M:%S')           ║"
echo "╚════════════════════════════════════════════╝"
echo ""

gcp_ok=false
aws_ok=false
github_ok=false
local_ok=false

# Check GCP Secret Manager
echo "GCP Secret Manager:"
echo -n "  Health: "

if gcloud secrets list 2>/dev/null | grep -q docker-hub-pat; then
  echo "✓ HEALTHY (docker-hub-pat accessible)"
  gcp_ok=true
else
  echo "✗ UNHEALTHY (cannot access docker-hub-pat)"
fi
echo ""

# Check AWS Secrets Manager
echo "AWS Secrets Manager:"
echo -n "  Health: "

if aws secretsmanager get-secret-value \
  --secret-id docker-hub-pat \
  --region us-east-1 >/dev/null 2>&1; then
  echo "✓ HEALTHY (docker-hub-pat accessible)"
  aws_ok=true
else
  echo "✗ UNHEALTHY (cannot access docker-hub-pat)"
fi
echo ""

# Check GitHub Encrypted Secrets
echo "GitHub Encrypted Secrets:"
echo -n "  Health: "

if [[ -n "${DOCKER_HUB_PAT_BACKUP:-}" ]]; then
  echo "✓ HEALTHY (DOCKER_HUB_PAT_BACKUP set)"
  github_ok=true
else
  echo "✗ UNHEALTHY (DOCKER_HUB_PAT_BACKUP not set)"
fi
echo ""

# Check Local Encrypted Backup
echo "Local Encrypted Backup:"
echo -n "  Health: "

if [[ -f ".secret-backup/docker-hub-pat.encrypted" ]]; then
  echo "✓ HEALTHY (encrypted backup file exists)"
  local_ok=true
else
  echo "✗ UNHEALTHY (no encrypted backup found)"
fi
echo ""

# Summary
echo "╔════════════════════════════════════════════╗"

healthy_count=0
[[ "$gcp_ok" == "true" ]] && ((healthy_count++))
[[ "$aws_ok" == "true" ]] && ((healthy_count++))
[[ "$github_ok" == "true" ]] && ((healthy_count++))
[[ "$local_ok" == "true" ]] && ((healthy_count++))

if [[ $healthy_count -ge 2 ]]; then
  echo "║  STATUS: ✓ PRODUCTION READY               ║"
  echo "║  $healthy_count/4 tiers healthy            ║"
else
  echo "║  STATUS: ⚠ DEGRADED MODE                  ║"
  echo "║  $healthy_count/4 tiers healthy            ║"
fi
echo "╚════════════════════════════════════════════╝"

# Exit with error if not enough tiers healthy
[[ $healthy_count -ge 2 ]] && exit 0 || exit 1
