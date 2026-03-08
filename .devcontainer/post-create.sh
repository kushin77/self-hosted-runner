#!/usr/bin/env bash
# Post-create setup for development container
# This runs after the devcontainer is created with features

set -euo pipefail

echo "🚀 Setting up Self-Hosted Runner dev environment..."

# Update system packages
echo "📦 Updating system packages..."
sudo apt-get update && sudo apt-get upgrade -y

# Install quality tools
echo "🔧 Installing quality checking tools..."
sudo apt-get install -y \
  shellcheck \
  yamllint \
  jq \
  yq \
  git-lfs \
  || true

# Install Node.js global tools
echo "📦 Installing Node.js tools..."
npm install -g \
  prettier \
  eslint \
  @typescript-eslint/eslint-plugin \
  @typescript-eslint/parser \
  || true

# Install Python tools
echo "🐍 Installing Python tools..."
pip install --upgrade \
  pip \
  pre-commit \
  pytest \
  pytest-cov \
  ruff \
  mypy \
  black \
  || true

# Install Go tools for testing
echo "🔨 Installing Go tools..."
go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest 2>/dev/null || true

# Pre-commit hooks
echo "🎣 Setting up pre-commit hooks..."
if [ -f ".pre-commit-config.yaml" ]; then
  pre-commit install || true
else
  echo "⊘ No .pre-commit-config.yaml found"
fi

# Bootstrap repo dependencies
echo "📚 Installing repository dependencies..."
if [ -f "package.json" ]; then
  npm install || true
fi
if [ -f "requirements.txt" ]; then
  pip install -r requirements.txt || true
fi

# Create directories if needed
echo "📁 Creating necessary directories..."
mkdir -p logs
mkdir -p tmp
mkdir -p .cache

# Git configuration
echo "🔐 Configuring Git..."
git config --global pull.rebase true
git config --global fetch.prune true

echo ""
echo "✅ Dev environment ready!"
echo ""
echo "📋 Quick reference:"
echo "  make help             - Show all available targets"
echo "  make quality          - Run quality checks"
echo "  make dev-up           - Start local dev stack"
echo "  make test             - Run tests"
echo "  make bootstrap        - Install all dependencies"
echo ""
echo "🌐 Services will be available at:"
echo "  Portal UI:        http://localhost:3000"
echo "  Provisioner API:  http://localhost:8000"
echo "  VaultShim:        http://localhost:8080"
echo "  Prometheus:       http://localhost:9090"
echo ""
