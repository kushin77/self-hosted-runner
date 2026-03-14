#!/usr/bin/env bash
set -euo pipefail
DOMAIN="${1:-}"
if [[ -z "${DOMAIN}" ]]; then
  echo "Usage: $0 <domain>"
  exit 2
fi
echo "Planned rebuild domain: ${DOMAIN}"
echo "This script intentionally scaffolds only and does not deploy resources."
