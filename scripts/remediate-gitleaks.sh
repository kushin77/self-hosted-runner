#!/usr/bin/env bash
set -euo pipefail

# Lightweight automated gitleaks remediation helper
# - Default: dry-run (lists matches)
# - --apply: replace matched secret lines with a placeholder and create .bak backups
# - Produces a summary at /tmp/gitleaks_remediation_summary.txt

DRY_RUN=true
if [[ ${1:-} == "--apply" ]]; then
  DRY_RUN=false
fi

EXCLUDE_DIRS=(\.git node_modules vendor .venv .venv3)
GREP_EXCLUDE_ARGS=()
for d in "${EXCLUDE_DIRS[@]}"; do
  GREP_EXCLUDE_ARGS+=(--exclude-dir="$d")
done

PATTERNS=(
  "-----BEGIN (RSA|PRIVATE|OPENSSH|ENCRYPTED) PRIVATE KEY-----"
  "AKIA[0-9A-Z]{16}"
  "ghp_[A-Za-z0-9_]{36}"
<REDACTED_SECRET_REMOVED_BY_AUTOMATION>
<REDACTED_SECRET_REMOVED_BY_AUTOMATION>
<REDACTED_SECRET_REMOVED_BY_AUTOMATION>
<REDACTED_SECRET_REMOVED_BY_AUTOMATION>
  "-----BEGIN CERTIFICATE-----"
)

TMP_MATCHES=/tmp/gitleaks_matches_$(date +%s).txt
SUMMARY=/tmp/gitleaks_remediation_summary.txt
>"$TMP_MATCHES"
>"$SUMMARY"

echo "Scanning repository for common secret patterns (dry-run=${DRY_RUN})..." | tee -a "$SUMMARY"

for pat in "${PATTERNS[@]}"; do
  echo "Searching pattern: $pat" >>"$SUMMARY"
  # shellcheck disable=SC2086
  grep -RIn --color=never -E "$pat" "./" "${GREP_EXCLUDE_ARGS[@]}" 2>/dev/null | tee -a "$TMP_MATCHES" >>"$SUMMARY" || true
done

MATCH_COUNT=$(wc -l < "$TMP_MATCHES" | tr -d ' ')
echo "Total matches: $MATCH_COUNT" | tee -a "$SUMMARY"

if $DRY_RUN; then
  echo "Dry-run complete. Review $TMP_MATCHES and $SUMMARY." >&2
  exit 0
fi

echo "Applying automated replacements (creating .bak backups)." | tee -a "$SUMMARY"
REPLACEMENT="<REDACTED_SECRET_REMOVED_BY_AUTOMATION>"

while IFS=: read -r file line rest; do
  # Only modify files that still exist
  if [[ -f "$file" ]]; then
    # create backup
    cp -- "$file" "$file.bak"
    # Replace matching lines with placeholder (safe, single-line replacement)
    perl -0777 -pe "s/(^.*(?:$rest).*\n+)/$REPLACEMENT\n/gim" -i -- "$file" || true
    echo "Patched: $file" | tee -a "$SUMMARY"
  fi
done < <(cat "$TMP_MATCHES")

echo "Staging changes for git commit..." | tee -a "$SUMMARY"
git add -A
echo "Done. Please review changes and push from the remediation branch." | tee -a "$SUMMARY"

echo "Summary written to $SUMMARY" >&2

exit 0
