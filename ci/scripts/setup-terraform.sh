#!/usr/bin/env bash
set -euo pipefail

# setup-terraform.sh
# Installs Terraform CLI on the runner.

TERRAFORM_VERSION="${1:-1.5.9}"

if command -v terraform >/dev/null 2>&1; then
  echo "terraform already installed: $(terraform version -json | jq -r .terraform_version)"
  exit 0
fi

ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
  ARCH=amd64
elif [[ "$ARCH" == "aarch64" ]]; then
  ARCH=arm64
fi

TARBALL="terraform_${TERRAFORM_VERSION}_linux_${ARCH}.zip"
URL="https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/${TARBALL}"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

curl -fsSL "$URL" -o "$TMPDIR/$TARBALL"
unzip -q "$TMPDIR/$TARBALL" -d "$TMPDIR"
if command -v sudo >/dev/null 2>&1; then
  sudo mv "$TMPDIR/terraform" /usr/local/bin/terraform
else
  mkdir -p "$HOME/.local/bin"
  mv "$TMPDIR/terraform" "$HOME/.local/bin/terraform"
  chmod +x "$HOME/.local/bin/terraform"
  export PATH="$HOME/.local/bin:$PATH"
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc" || true
fi

echo "terraform installed: $(terraform -version | head -n1)"
