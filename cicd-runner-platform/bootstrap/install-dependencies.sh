#!/usr/bin/env bash
##
## Install CI/CD Runner Dependencies
##
set -euo pipefail

# Detect OS
if grep -q "^ID=ubuntu" /etc/os-release; then
  OS="ubuntu"
elif grep -q "^ID=centos\|^ID=rhel" /etc/os-release; then
  OS="centos"
else
  OS="linux"
fi

echo "Installing dependencies for ${OS}..."

case "${OS}" in
  ubuntu)
    apt-get update
    apt-get install -y \
      curl \
      git \
      wget \
      ca-certificates \
      gnupg \
      lsb-release \
      software-properties-common \
      jq \
      awscli \
      docker.io \
      containerd \
      cri-o \
      systemd \
      ca-certificates \
      openssl \
      unzip
    ;;
  centos)
    yum groupinstall -y "Development Tools"
    yum install -y \
      curl \
      git \
      wget \
      ca-certificates \
      gnupg \
      jq \
      aws-cli \
      docker \
      containerd \
      cri-o \
      systemd \
      openssl \
      unzip
    ;;
  *)
    echo "Unsupported OS. Please install dependencies manually."
    exit 1
    ;;
esac

# Ensure Docker daemon is enabled and running
systemctl enable docker || true
systemctl start docker || true

# Install Docker Compose if not present
if ! command -v docker-compose &>/dev/null; then
  curl -L "https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-$(uname -s)-$(uname -m)" \
    -o /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose
fi

# Install additional security tools
curl -sSL https://get.docker.com | sh || true

# Install OPA/Conftest for policy evaluation
if ! command -v conftest &>/dev/null; then
  wget -qO /tmp/conftest.tar.gz https://github.com/open-policy-agent/conftest/releases/download/v0.45.0/conftest_0.45.0_Linux_x86_64.tar.gz
  tar xf /tmp/conftest.tar.gz -C /usr/local/bin/
  rm /tmp/conftest.tar.gz
fi

# Install Cosign for artifact signing
if ! command -v cosign &>/dev/null; then
  wget -qO /usr/local/bin/cosign https://github.com/sigstore/cosign/releases/download/v2.0.0/cosign-linux-amd64
  chmod +x /usr/local/bin/cosign
fi

# Install Syft for SBOM generation
if ! command -v syft &>/dev/null; then
  curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin
fi

# Install NATS CLI for distributed coordination (optional)
if ! command -v nats &>/dev/null; then
  wget -qO /tmp/nats.zip https://github.com/nats-io/natscli/releases/download/v0.1.0/nats-0.1.0-linux-amd64.zip
  unzip -o /tmp/nats.zip -d /usr/local/bin/
  rm /tmp/nats.zip
fi

echo "✓ Dependencies installed successfully"
