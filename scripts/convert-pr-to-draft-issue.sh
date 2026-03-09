#!/usr/bin/env bash
# Convert PR language in Markdown docs to 'draft issue' to reflect current ops policy
set -euo pipefail

ROOT_DIR="$(dirname "$(dirname "${BASH_SOURCE[0]}")")"
echo "Scanning Markdown files under $ROOT_DIR for PR wording..."

find "$ROOT_DIR" -type f -name '*.md' -print0 | while IFS= read -r -d '' file; do
  # Skip files under .git and vendor dirs
  case "$file" in
    */.git/*|*/.venv-*/*|*/node_modules/*) continue ;;
  esac

  sed -E \
    -e 's/\b[Pp]ull request\b/Draft issue/g' \
    -e 's/\b[Pp]ull Request\b/Draft Issue/g' \
    -e 's/\bPR: /Draft Issue: /g' \
    -e 's/\bPRs\b/Draft issues/g' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
done

echo "Conversion complete. Review changed files before committing."
