#!/usr/bin/env bash
set -euo pipefail
# Apply migration dry-run: iterate migration-report and call provider push scripts with --dry-run
REPORT="${1:-migration-report-$(date -u +%Y-%m-%d).json}"
if [ ! -f "$REPORT" ]; then echo "Report $REPORT not found" >&2; exit 2; fi

echo "Running dry-run migration using $REPORT"
mkdir -p .migration-audit

jq -c '.migrations[]' "$REPORT" | while read -r rec; do
  name=$(echo "$rec" | jq -r '.name')
  target=$(echo "$rec" | jq -r '.recommended_target')
  echo "Dry-run: $name -> $target"
  case "$target" in
    gsm)
        bash scripts/migrate/push-to-gsm.sh --name "$name" --value "DRY_RUN_PLACEHOLDER" --dry-run || true
      ;;
    vault)
        bash scripts/migrate/push-to-vault.sh --name "$name" --value "DRY_RUN_PLACEHOLDER" --dry-run || true
      ;;
    kms)
        bash scripts/migrate/push-to-kms.sh --name "$name" --value "DRY_RUN_PLACEHOLDER" --dry-run || true
      ;;
    *)
      echo "Unknown target: $target" >&2
      ;;
  esac
done

echo "Dry-run migration complete. Audit logs in .migration-audit/"
