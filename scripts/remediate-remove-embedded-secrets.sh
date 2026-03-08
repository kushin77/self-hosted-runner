#!/usr/bin/env bash
set -euo pipefail

# remediation script: dry-run by default; use --apply to change files
DRY_RUN=true
if [[ "${1:-}" == "--apply" ]]; then
  DRY_RUN=false
fi

ROOT_DIR="$(pwd)"
REPORT="${ROOT_DIR}/remediation-report.txt"
rm -f "$REPORT"

PATTERNS=(
  "-----BEGIN OPENSSH PRIVATE KEY-----"
  "-----BEGIN PRIVATE KEY-----"
  "-----BEGIN RSA PRIVATE KEY-----"
  "AKIA[0-9A-Z]{16}"
  "ghp_[A-Za-z0-9]{36}"
  "AIza[0-9A-Za-z_\-]{35}"
)

echo "Remediation run: dry-run=$DRY_RUN" > "$REPORT"
echo "Scanning for embedded secrets..." >> "$REPORT"

# Find candidate files (exclude .git and vendor directories)
FILES=$(grep -RIn --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=vendor -E "${PATTERNS[0]}|${PATTERNS[1]}|${PATTERNS[2]}|${PATTERNS[3]}|${PATTERNS[4]}|${PATTERNS[5]}" || true)

if [[ -z "$FILES" ]]; then
  echo "No matches found." >> "$REPORT"
  cat "$REPORT"
  exit 0
fi

echo "Matches:" >> "$REPORT"
echo "$FILES" >> "$REPORT"

if $DRY_RUN; then
  echo "Dry-run: no files changed. To apply fixes, run: $0 --apply" >> "$REPORT"
  cat "$REPORT"
  exit 0
fi

echo "Applying replacements (backups to .bak)..." >> "$REPORT"
while IFS= read -r line; do
  file=$(echo "$line" | cut -d: -f1)
  lineno=$(echo "$line" | cut -d: -f2)
  # create backup once
  if [[ ! -f "$file.bak" ]]; then
    cp -p "$file" "$file.bak"
  fi
  # perform safe replacement: do not write secret values to report
  perl -0777 -pe 's/(-----BEGIN [\w\s]+KEY-----.*?-----END [\w\s]+KEY-----)/[REDACTED_SECRET_REMOVED_BY_AUTOMATED_REMEDIATION]/sg' -i "$file"
  perl -0777 -pe 's/(AKIA[0-9A-Z]{16})/[REDACTED_SECRET_KEY]/sg' -i "$file"
  perl -0777 -pe 's/(ghp_[A-Za-z0-9]{36})/[REDACTED_GITHUB_PAT]/sg' -i "$file"
  perl -0777 -pe 's/(AIza[0-9A-Za-z_\-]{35})/[REDACTED_GOOGLE_API_KEY]/sg' -i "$file"
  echo "Replaced secrets in: $file (original saved as $file.bak)" >> "$REPORT"
done <<< "$FILES"

echo "Remediation complete. See $REPORT for details." >> "$REPORT"
cat "$REPORT"
