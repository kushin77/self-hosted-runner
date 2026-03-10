#!/usr/bin/env bash
set -euo pipefail

TS=$(date -u +%Y%m%dT%H%M%SZ)
OUT_DIR="nexusshield/ops/deploy_bundle"
mkdir -p "$OUT_DIR"
OUTFILE="/tmp/nexusshield-deploy-${TS}.tar.gz"

echo "Creating deployment bundle: $OUTFILE"

FILES=(
  "nexusshield/systemd/nexusshield-credential-rotation.service"
  "nexusshield/systemd/nexusshield-credential-rotation.timer"
  "nexusshield/systemd/README.md"
  "nexusshield/scripts/credential-rotation.sh"
  "nexusshield/scripts/init-audit-trail.sh"
  "nexusshield/scripts/fix-audit-logs.sh"
  "nexusshield/infrastructure/terraform/README_DEPLOY.md"
  "nexusshield/ops/deploy_bundle/verify_and_append_audit.sh"
  "nexusshield/ops/deploy_bundle/INSTALL.md"
)

# Only include files that exist
TOAR=()
for f in "${FILES[@]}"; do
  if [ -f "$f" ]; then
    TOAR+=("$f")
  else
    echo "Warning: missing $f — skipping"
  fi
done

if [ ${#TOAR[@]} -eq 0 ]; then
  echo "No files to bundle; aborting." >&2
  exit 1
fi

tar -czf "$OUTFILE" "${TOAR[@]}"

SHA=$(sha256sum "$OUTFILE" | awk '{print $1}')
echo "$OUTFILE $SHA"

# Copy bundle into repo ops folder for easy download (optional)
DEST="$OUT_DIR/$(basename "$OUTFILE")"
cp "$OUTFILE" "$DEST"
echo "Bundle copied to $DEST"
echo "$SHA" > "$DEST.sha256"
echo "Created bundle and checksum: $DEST.sha256"

echo "$DEST"
