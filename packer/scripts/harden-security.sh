#!/usr/bin/env bash
set -euo pipefail

echo "==> Applying basic hardening"

# Create non-root runner user
USER=runner
if ! id -u ${USER} >/dev/null 2>&1; then
  useradd --system --create-home --shell /bin/bash ${USER}
fi

# Add runner to docker group if docker exists
if getent group docker >/dev/null 2>&1; then
  usermod -aG docker ${USER} || true
fi

# Disable SSH root login password authentication
if [ -f /etc/ssh/sshd_config ]; then
  sed -i 's/^PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config || true
  sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config || true
  systemctl reload sshd || true
fi

# Kernel hardening (minimal)
sysctl -w net.ipv4.ip_forward=0
sysctl -w net.ipv4.conf.all.accept_source_route=0
sysctl -w net.ipv4.conf.all.accept_redirects=0
sysctl -w net.ipv4.conf.all.secure_redirects=0

echo 'fs.suid_dumpable=0' >> /etc/sysctl.d/99-runner-hardening.conf || true
sysctl --system || true

echo "==> Hardening complete"
