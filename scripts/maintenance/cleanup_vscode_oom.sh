#!/usr/bin/env bash
set -euo pipefail

# Cleanup script to keep remote SSH workspace small and VS Code server stable.
# Idempotent and safe: it only removes caches, temporary data, and moves large
# extensions to an "extensions-disabled" folder for later review.

LOG="/var/log/vscode_oom_maintenance.log"
mkdir -p "$(dirname "$LOG")" || true

timestamp(){ date -Iseconds; }
echo "$(timestamp) : starting maintenance" >> "$LOG"

# 1) Remove Code/Backups and vscode-server backups
rm -rf "$HOME/.config/Code/Backups"/* 2>/dev/null || true
rm -rf "$HOME/.local/share/code/Backups"/* 2>/dev/null || true
rm -rf "$HOME/.vscode-server/data/Backups"/* 2>/dev/null || true

echo "$(timestamp) : removed VS Code backup dirs" >> "$LOG"

# 2) Remove terraform caches (safe to re-init)
find "$PWD" -type d -name '.terraform' -prune -exec rm -rf {} + 2>/dev/null || true
echo "$(timestamp) : removed .terraform caches" >> "$LOG"

# 3) Clean actions-runner work folders
if [ -d "$PWD/actions-runner/_work" ]; then
  rm -rf "$PWD/actions-runner/_work"/* 2>/dev/null || true
  rmdir "$PWD/actions-runner/_work" 2>/dev/null || true
  echo "$(timestamp) : cleaned actions-runner/_work" >> "$LOG"
fi

# 4) Run git gc on the workspace root (cheap, safe)
if [ -d ".git" ]; then
  git -C "$PWD" gc --prune=now || true
  echo "$(timestamp) : git gc run" >> "$LOG"
fi

# 5) Move heavy vscode-server extensions (>50MB) to extensions-disabled
EXT_DIR="$HOME/.vscode-server/extensions"
DISABLED_DIR="$HOME/.vscode-server/extensions-disabled"
mkdir -p "$DISABLED_DIR"
if [ -d "$EXT_DIR" ]; then
  while IFS= read -r -d '' ext; do
    size=$(du -s --block-size=1M "$ext" 2>/dev/null | cut -f1 || echo 0)
    if [ "$size" -ge 50 ]; then
      mv "$ext" "$DISABLED_DIR/" || true
      echo "$(timestamp) : moved $(basename "$ext") to extensions-disabled ($size MB)" >> "$LOG"
    fi
  done < <(find "$EXT_DIR" -maxdepth 1 -mindepth 1 -type d -print0)
fi

# 6) Trim old VS Code server logs >30 days
find "$HOME/.vscode-server/data/logs" -type f -mtime +30 -delete 2>/dev/null || true
echo "$(timestamp) : rotated old logs" >> "$LOG"

echo "$(timestamp) : maintenance completed" >> "$LOG"

exit 0
