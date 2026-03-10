#!/usr/bin/env bash
set -euo pipefail

# Helper to run terraform_pin_updater with a mappings file and commit changes
WORKDIR="$(cd "$(dirname "$0")/.." && pwd)"
MAPFILE="$WORKDIR/ci/image_pin_mappings.json"
MSG="chore: automated image pin update"

if [ ! -f "$MAPFILE" ]; then
  echo "Mapping file not found: $MAPFILE"
  exit 2
fi

python3 "$WORKDIR/tools/terraform_pin_updater.py" --path "$WORKDIR/terraform" --map-file "$MAPFILE" --commit "$MSG"
