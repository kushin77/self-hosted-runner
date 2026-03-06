#!/usr/bin/env bash
set -euo pipefail

# install_kubeseal_helper.sh
# Download `kubeseal` client binary into infra/tools and print install notes.
# Does not perform system-wide install (requires sudo). Safe for CI/workspace.
# Usage: ./scripts/ci/install_kubeseal_helper.sh [version]

VERSION=${1:-0.20.0}
OUTDIR=infra/tools
BIN_NAME=kubeseal
ARCH=linux-amd64

mkdir -p "$OUTDIR"
URL="https://github.com/bitnami/sealed-secrets/releases/download/v${VERSION}/kubeseal-${VERSION}-${ARCH}.tar.gz"

echo "Downloading kubeseal v${VERSION} from ${URL} (to ${OUTDIR})"
curl -L "$URL" -o /tmp/kubeseal.tar.gz
tar -xzf /tmp/kubeseal.tar.gz -C /tmp
mv /tmp/kubeseal "$OUTDIR/"
chmod +x "$OUTDIR/kubeseal"
rm -f /tmp/kubeseal.tar.gz

echo "kubeseal installed to ${OUTDIR}/kubeseal"
echo "To use it in this session: export PATH=\"$(pwd)/${OUTDIR}:$PATH\""
echo "For cluster-wide use, move it to /usr/local/bin with sudo: sudo mv ${OUTDIR}/kubeseal /usr/local/bin/"
