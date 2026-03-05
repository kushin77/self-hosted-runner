#!/usr/bin/env bash
# Generate an SBOM for the repo using syft (requires syft installed)

if ! command -v syft >/dev/null 2>&1; then
  echo "syft not installed; please install from https://github.com/anchore/syft" >&2
  exit 1
fi

echo "Generating SBOM to sbom.json"
syft packages dir:./ -o json > sbom.json
