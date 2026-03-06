#!/usr/bin/env bash
set -euo pipefail

# setup-python.sh
# Installs a CPython runtime on the runner (uses official Python.org binaries where available).

PY_VERSION="${1:-3.11}"

echo "Setting up Python ${PY_VERSION}"

if command -v python3 >/dev/null 2>&1; then
  INSTALLED=$(python3 --version 2>&1 | awk '{print $2}')
  if [[ "$INSTALLED" == ${PY_VERSION}* ]]; then
    echo "Python $INSTALLED already installed; skipping"
    exit 0
  fi
fi

ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
  ARCH=amd64
elif [[ "$ARCH" == "aarch64" ]]; then
  ARCH=arm64
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "Downloading python binaries"
TARBALL="Python-${PY_VERSION}.tgz"
URL="https://www.python.org/ftp/python/${PY_VERSION}/${TARBALL}"
curl -fsSL "$URL" -o "$TMPDIR/$TARBALL"
tar -xzf "$TMPDIR/$TARBALL" -C "$TMPDIR"

cd "$TMPDIR/Python-${PY_VERSION}"
if command -v sudo >/dev/null 2>&1; then
  ./configure --enable-optimizations --prefix=/usr/local
  make -j2
  sudo make altinstall
else
  ./configure --enable-optimizations --prefix="$HOME/.local"
  make -j2
  make altinstall
  export PATH="$HOME/.local/bin:$PATH"
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc" || true
fi

echo "Python setup complete: $(python3 --version)"
