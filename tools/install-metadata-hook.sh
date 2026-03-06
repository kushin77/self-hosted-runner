#!/usr/bin/env bash
set -euo pipefail
# Installs a git pre-commit hook that validates metadata files before commit.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK_PATH="$ROOT/.git/hooks/pre-commit"
cat > "$HOOK_PATH" <<'HOOK'
#!/usr/bin/env bash
python3 scripts/generate_function_metadata.py --validate --output /tmp/portal-artifact-precommit.json || {
  echo "Metadata validation failed. Fix metadata or run scripts/generate_function_metadata.py --validate" >&2
  exit 1
}
HOOK
chmod +x "$HOOK_PATH"
echo "Installed pre-commit hook"
