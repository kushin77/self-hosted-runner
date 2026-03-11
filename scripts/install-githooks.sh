#!/usr/bin/env bash
set -euo pipefail

# Install repository git hooks from .githooks into .git/hooks
ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
HOOKS_DIR="$ROOT_DIR/.githooks"
GIT_HOOKS_DIR="$ROOT_DIR/.git/hooks"

if [ ! -d "$HOOKS_DIR" ]; then
  echo "No .githooks directory found; nothing to install." >&2
  exit 0
fi

if [ ! -d "$GIT_HOOKS_DIR" ]; then
  echo "No .git/hooks directory found; ensure this is a git repo." >&2
  exit 1
fi

for f in "$HOOKS_DIR"/*; do
  [ -e "$f" ] || continue
  basename=$(basename "$f")
  dest="$GIT_HOOKS_DIR/$basename"
  echo "Installing hook $basename -> $dest"
  cp "$f" "$dest"
  chmod +x "$dest"
done

echo "Hooks installed."
