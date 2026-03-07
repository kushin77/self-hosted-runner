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
