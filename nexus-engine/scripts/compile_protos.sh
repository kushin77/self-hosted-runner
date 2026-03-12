#!/usr/bin/env bash
set -euo pipefail

# Usage: run on fullstack where protoc and protoc-gen-go are installed
cd "$(dirname "$0")/.." || exit 1

echo "Compiling proto/discovery.proto to Go package pkg/discovery..."

protoc --go_out=paths=source_relative:./pkg --go_opt=paths=source_relative proto/discovery.proto

echo "Generated files:" 
ls -la pkg/discovery || true

echo "Done. Replace temporary pkg/discovery stubs with generated files if present." 
