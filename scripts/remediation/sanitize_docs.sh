#!/usr/bin/env bash
set -euo pipefail
# Sanitize documentation and example files by replacing literal credential patterns
# This operates on markdown and example files only. Use with caution.

ROOT=$(git rev-parse --show-toplevel)
FILES=$(git ls-files "*.md" "*.md.bak" "*.example" "secrets.env.template" "backend/.env.example" docs/** | tr '\n' ' ')
if [ -z "$FILES" ]; then
  echo "No doc/example files tracked to sanitize.";
  exit 0
fi

echo "Sanitizing files: $FILES"
for f in $FILES; do
  [ -f "$f" ] || continue
  # Use sed for simpler, more compatible replacements
  sed -i 's/AKIA[0-9A-Z]\{16\}/AKIA_REDACTED/g' "$f" || true
  sed -i 's/ghp_[A-Za-z0-9_]\{30,\}/GITHUB_PAT_REDACTED/g' "$f" || true
  sed -i 's/"private_key"[[:space:]]*:[[:space:]]*"[^"]*"/"private_key": "REDACTED"/g' "$f" || true
  # Replace base64-looking blobs (40+ chars of base64)
  sed -i -E 's/[A-Za-z0-9+\/]{40,}={0,2}/BASE64_BLOB_REDACTED/g' "$f" || true
  git add "$f"
done

if git diff --cached --quiet; then
  echo "No changes after sanitization."
  exit 0
fi

git commit -m "chore(secrets): sanitize docs and examples to remove literal credential examples"
echo "Sanitization committed. Review changes before rewriting history."
