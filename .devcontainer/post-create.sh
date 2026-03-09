#!/bin/bash
set -euo pipefail

echo "📦 Installing dev tools in devcontainer..."

# Update and install CLI tools
apt-get update -qq
apt-get install -y -qq \
  shellcheck \
  jq \
  yq \
  curl \
  git \
  make

# Install Terraform
echo "Installing Terraform..."
cd /tmp && \
  curl -fsSL https://apt.releases.hashicorp.com/gpg | apt-key add - && \
  apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main" && \
  apt-get update -qq && \
  apt-get install -y -qq terraform

# Install Node.js (for local service dev)
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt-get install -y -qq nodejs

# Install Python dev
apt-get install -y -qq python3-dev python3-pip python3-venv
pip3 install --quiet --disable-pip-version-check pyyaml requests

echo "✅ Devcontainer setup complete!"
