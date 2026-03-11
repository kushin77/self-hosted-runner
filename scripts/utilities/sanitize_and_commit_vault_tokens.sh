#!/usr/bin/env bash
set -euo pipefail
# Searches the repository for occurrences of the literal substring "VAULT_TKN" (and related variants)
# and replaces them with sanitized names (VAULT_TKN, VAULT_TKN_FILE, VAULT_TKN_MOUNT_PATH).
# Backs up modified files with a .bak extension and commits changes.

cd "$(git rev-parse --show-toplevel)"

# Parse options
DRY_RUN=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    *)
      echo "Usage: $0 [--dry-run]"
      exit 1
      ;;
  esac
done

echo "Scanning tracked files for 'VAULT_TKN' patterns..."
# Use git grep to find occurrences only in tracked files (avoid build/coverage/logs)
mapfile -t files < <(git grep -Il "VAULT_TKN" || true)
if [[ ${#files[@]} -eq 0 ]]; then
  echo "No tracked files contain 'VAULT_TKN'. Nothing to do."
  exit 0
fi

echo "Found ${#files[@]} files."
if [[ "$DRY_RUN" == "true" ]]; then
  echo "[DRY-RUN] Would sanitize:"
  printf '%s\n' "${files[@]}"
  exit 0
fi

echo "Making backups and applying replacements..."
for f in "${files[@]}"; do
  echo " - $f"
  cp -- "$f" "$f.bak"
  # Sanitize with proper redaction replacements
  sed -i.tmp \
    -e 's/vault_token\s*=\s*[^\n]*/vault_token=REDACTED/gi' \
    -e 's/VAULT_TOKEN\s*=\s*[^\n]*/VAULT_TOKEN=REDACTED/gi' \
    -e 's/\bVAULT_TKN\b/VAULT_TKN_REDACTED/g' \
    "$f"
  rm -f "$f.tmp"
done

echo "Re-checking for remaining tracked matches..."
if git grep -Il "VAULT_TKN" >/dev/null 2>&1; then
  echo "ERROR: Some tracked occurrences remain after replacement. Restoring backups and aborting."
  for f in "${files[@]}"; do mv -f "$f.bak" "$f"; done
  exit 1
fi

echo "Staging modified files and committing..."
git add -- "${files[@]}"
git commit -m "chore(scripts): sanitize VAULT_TKN markers -> VAULT_TKN (auto)"

echo "Sanitization and commit complete."
exit 0
