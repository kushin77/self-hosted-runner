#!/usr/bin/env bash
set -euo pipefail

# Usage: verify_and_append_audit.sh /path/to/bundle.tar.gz
BUCKET_AUDIT_FILE="nexusshield/logs/deployment-audit.jsonl"

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 /path/to/bundle.tar.gz" >&2
  exit 2
fi

BUNDLE="$1"

if [ ! -f "$BUNDLE" ]; then
  echo "Bundle not found: $BUNDLE" >&2
  exit 3
fi

SHA=$(sha256sum "$BUNDLE" | awk '{print $1}')
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# basic smoke checks
echo "Verifying systemd units (not installing)"
for unit in nexusshield-credential-rotation.service nexusshield-credential-rotation.timer; do
  if systemctl list-unit-files | grep -q "$unit"; then
    echo "Unit present: $unit"
  else
    echo "Unit missing (expected to be installed out-of-band): $unit"
  fi
done

# Create audit JSONL entry
JSON=$(cat <<EOF
{"timestamp":"$TS","event":"out_of_band_deploy","bundle_sha256":"$SHA","deployed_by":"ops:manual","notes":"out-of-band deploy bundle verification"}
EOF
)

mkdir -p "$(dirname "$BUCKET_AUDIT_FILE")"
printf '%s
'"$JSON" >> "$BUCKET_AUDIT_FILE"

echo "Appended audit entry to $BUCKET_AUDIT_FILE"
echo "$JSON"
