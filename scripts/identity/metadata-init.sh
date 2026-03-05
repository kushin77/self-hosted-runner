#!/usr/bin/env bash
set -euo pipefail

# metadata-init.sh
# Fetches expected Vault Agent artifacts from GCP instance metadata and writes
# them to disk so services can be enabled without baking new images.

METADATA_URL_BASE="http://169.254.169.254/computeMetadata/v1/instance/attributes"
HEADERS=( -H "Metadata-Flavor: Google" )

OUT_DIR="/etc/vault-agent"
SYSTEMD_DIR="/etc/systemd/system"
BIN_DIR="/usr/local/bin"

declare -a KEYS=("vault-agent.hcl" "vault-agent.service" "registry-creds.tpl" "vault-renewal.sh")

mkdir -p "$OUT_DIR"
mkdir -p "$BIN_DIR"

for key in "${KEYS[@]}"; do
  url="$METADATA_URL_BASE/$key"
  if content=$(curl -fsS "${HEADERS[@]}" "$url" 2>/dev/null || true); then
    if [[ -n "$content" ]]; then
      case "$key" in
        *.service)
          dest="$SYSTEMD_DIR/$key"
          echo "$content" > "$dest"
          ;;
        *.sh)
          dest="$BIN_DIR/$key"
          echo "$content" > "$dest"
          chmod +x "$dest"
          ;;
        *)
          dest="$OUT_DIR/$key"
          echo "$content" > "$dest"
          ;;
      esac
      echo "Wrote metadata key $key to $dest"
    fi
  fi
done

# If systemctl is available, reload and enable services present
if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload || true
  if [[ -f "$SYSTEMD_DIR/vault-agent.service" ]]; then
    systemctl enable --now vault-agent.service || true
  fi
  if [[ -f "$SYSTEMD_DIR/vault-renewal.service" ]]; then
    systemctl enable --now vault-renewal.service || true
  fi
fi

echo "metadata-init completed"
