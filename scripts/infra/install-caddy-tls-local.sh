#!/usr/bin/env bash
set -euo pipefail
REPO_DIR="/home/akushnir/self-hosted-runner"
DROPIN_SRC="${REPO_DIR}/config/systemd/caddy.service.d/eiq-config.conf"
DROPIN_DST="/etc/systemd/system/caddy.service.d/eiq-config.conf"
CERT_DIR="/etc/caddy/ssl"
CADDYFILE_SRC="${REPO_DIR}/config/caddy/Caddyfile"
CADDYFILE_DST="/etc/caddy/Caddyfile"

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo bash $0" >&2; exit 1
fi

# Check cert and key in homedir
REAL_HOME=$(getent passwd "${SUDO_USER:-$(logname)}" | cut -d: -f6)
KEY_HOMEDIR="${REAL_HOME}/.eiq-certs"
if [[ ! -f "${KEY_HOMEDIR}/cf_origin.key" ]]; then
  echo "Private key not found at ${KEY_HOMEDIR}/cf_origin.key" >&2
  echo "Place your Cloudflare origin key there and re-run. Exiting."; exit 1
fi

# Install cert+key
mkdir -p "$CERT_DIR"
cp "${KEY_HOMEDIR}/cf_origin.crt" "$CERT_DIR/"
cp "${KEY_HOMEDIR}/cf_origin.key" "$CERT_DIR/"
chmod 644 "${CERT_DIR}/cf_origin.crt" || true
chmod 640 "${CERT_DIR}/cf_origin.key" || true
chown root:caddy "${CERT_DIR}/cf_origin.key" 2>/dev/null || true

# Install Caddyfile
BACKUP="${CADDYFILE_DST}.bak.$(date +%Y%m%d%H%M%S)"
cp "$CADDYFILE_DST" "$BACKUP" 2>/dev/null || true
cp "$CADDYFILE_SRC" "$CADDYFILE_DST"

# Install systemd drop-in
mkdir -p "$(dirname "$DROPIN_DST")"
cp "$DROPIN_SRC" "$DROPIN_DST"
systemctl daemon-reload

# Validate Caddyfile if caddy binary exists
if command -v caddy &>/dev/null; then
  caddy validate --config "$CADDYFILE_DST" || { echo "Caddyfile invalid, restoring backup"; cp "$BACKUP" "$CADDYFILE_DST"; exit 1; }
  systemctl reload caddy
  echo "Caddy reloaded"
else
  echo "caddy binary not found on host — drop-in installed; ensure caddy is present and then run: systemctl restart caddy"
fi

echo "Done. Caddyfile installed to $CADDYFILE_DST and drop-in $DROPIN_DST created."
