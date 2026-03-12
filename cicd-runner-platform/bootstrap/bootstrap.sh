#!/usr/bin/env bash
set -euo pipefail

# Minimal bootstrap for self-provisioning runner node
# - clone repo subtree (already assumed present if running from repo)
# - install basic dependencies
# - verify host hardening (minimal checks)
# - run register-runner.sh

echo "== CI/CD Runner Bootstrap =="

# simple package checks (deb/apt example)
if command -v apt-get >/dev/null 2>&1; then
  sudo apt-get update -y
  sudo apt-get install -y curl git ca-certificates jq openssl || true
fi

# Host verification placeholder
echo "* Verifying host requirements..."
# Example checks: kernel namespaces, cgroups, available disk
if [ ! -f /proc/sys/kernel/unprivileged_userns_clone ]; then
  echo "* Warning: user namespaces may not be available"
fi

# Ensure repo present
if [ ! -d "$(pwd)/.." ]; then
  echo "Please clone repository to /opt/cicd-runner-platform and run this script from bootstrap/"
  exit 1
fi

# Run runner registration (non-destructive if already registered)
if [ -x "../runner/register-runner.sh" ]; then
  echo "* Registering runner (if needed)..."
  sudo bash ../runner/register-runner.sh || true
else
  echo "* register-runner.sh missing or not executable; skipping registration step"
fi

echo "Bootstrap complete. Runner should register and be ready to accept ephemeral jobs."
