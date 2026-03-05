#!/usr/bin/env bash
set -euo pipefail

# Simple generator for an image manifest. This is a scaffold; update with real
image list.
OUT=${1:-/dev/stdout}
cat > "$OUT" <<'YAML'
images:
  - name: grafana
    image: grafana/grafana:9.5.6
  - name: otel-collector
    image: otel/opentelemetry-collector-contrib:0.80.0
  - name: provisioner-worker
    image: ghcr.io/kushin77/provisioner-worker:latest
  - name: managed-auth
    image: ghcr.io/kushin77/managed-auth:latest
  - name: vault-shim
    image: ghcr.io/kushin77/vault-shim:latest
YAML

echo "Wrote manifest to $OUT"
