#!/usr/bin/env bash
set -euo pipefail

HOOK_DIR=".githooks"
if [ ! -d "$HOOK_DIR" ]; then
  echo "No $HOOK_DIR directory found" >&2
  exit 1
fi

for f in "$HOOK_DIR"/*; do
  name=$(basename "$f")
  dest=".git/hooks/$name"
  cp "$f" "$dest"
  chmod +x "$dest"
  echo "Installed hook $dest"
done

echo "Installed git hooks. Note: server-side enforcement should be used for strict policy." 
