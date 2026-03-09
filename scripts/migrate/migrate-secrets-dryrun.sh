#!/usr/bin/env bash
set -euo pipefail
# Dry-run migration: reads secrets-inventory JSON and outputs migration-report-<date>.json
INV_FILE="${1:-secrets-inventory-$(date -u +%Y-%m-%d).json}"
OUT_FILE="migration-report-$(date -u +%Y-%m-%d).json"
if [ ! -f "$INV_FILE" ]; then
  echo "Inventory file $INV_FILE not found" >&2
  exit 2
fi

echo "{\n  \"generated_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"," > "$OUT_FILE"
echo "  \"migrations\": [" >> "$OUT_FILE"

mapfile -t _names < <(jq -r '.repo_secrets[]?.name' "$INV_FILE" 2>/dev/null || true)
for name in "${_names[@]:-}"; do
  # classify: high-risk names -> GSM primary
  target="gsm"
  if echo "$name" | grep -Ei "(VAULT|KMS|AWS_ROLE|GCP_SERVICE_ACCOUNT|PRIVATE|SSH|KEY|TOKEN|SECRET)" >/dev/null; then
    target="vault"
  fi
  if echo "$name" | grep -Ei "(KMS|ENCRYPT)" >/dev/null; then
    target="kms"
  fi
  cat >> "$OUT_FILE" <<EOF
    {
      "name": "$name",
      "current_location": "repo_secret",
      "recommended_target": "$target",
      "migration_command": "# Dry-run: create $name in $target (provider CLI)"
    },
EOF
done

echo "  ]" >> "$OUT_FILE"
echo "}\n" >> "$OUT_FILE"

echo "Wrote migration report to $OUT_FILE"
