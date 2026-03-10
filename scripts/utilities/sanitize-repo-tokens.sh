#!/usr/bin/env bash
set -euo pipefail

# Redact token-like strings in documentation and logs to avoid accidental leakage
# Operates on .md, .yml, .yaml, .txt, .log files in repo root and subdirs

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "Sanitizing repository for token-like patterns..."

# Patterns to redact
# - hvs.<token>
# - s.<token> (short token prefixes)
# - dev-token-*
# - devroot
# - literal long-looking tokens in assignment patterns (e.g., export REDACTED=...)

FILES=$(git ls-files "*.md" "*.yml" "*.yaml" "*.txt" "*.log" || true)

for f in $FILES; do
  # Skip binary or large plan files under .git-rewrite/artifacts
  case "$f" in
    .git-rewrite/*|node_modules/*) continue ;;
  esac

  # Use perl for robust regex replacements
  perl -0777 -pe \
    "s/\b(hvs\.[A-Za-z0-9_\-\.]{3,})\b/<REDACTED>/g; \
     s/\b(s\.[A-Za-z0-9_\-]{6,})\b/<REDACTED>/g; \
     s/\bdev-token[-A-Za-z0-9_]+\b/<REDACTED>/g; \
     s/\bdevroot\b/<REDACTED>/g; \
     s/\b(REDACTED\s*=\s*)([^\s'\"]+)\b/\1<REDACTED>/g; \
     s/(export\s+REDACTED=)([^\s'\"]+)/\1<REDACTED>/g;" \
    -i "$f" || true

done

echo "Sanitization complete."
