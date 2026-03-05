#!/bin/sh
set -eu

echo "Running self-update SBOM integration test"

mkdir -p tests/artifacts
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

echo "fake-release" > "$tmpdir/release-content.txt"
tar -czf tests/artifacts/fake-art-sbom.tar.gz -C "$tmpdir" release-content.txt

ARTIFACT_PATH="$(pwd)/tests/artifacts/fake-art-sbom.tar.gz"

# Create a minimal fake SBOM JSON that contains 'syft' string to satisfy basic validation
SBOM_PATH="$(pwd)/tests/artifacts/fake-art-sbom.json"
cat > "$SBOM_PATH" <<'EOF'
{
  "sbom": "syft",
  "packages": [ { "name": "fake-release", "version": "0.0.1" } ]
}
EOF

rm -rf /home/akushnir/self-hosted-runner/releases || true
mkdir -p /home/akushnir/self-hosted-runner/releases

export SBOM_URL="$SBOM_PATH"
export SBOM_REQUIRED=1

# Run apply-update in no-service mode
sh self-update/apply-update.sh --current self-update/version --artifact-url "$ARTIFACT_PATH" --no-service

if [ -L "/home/akushnir/self-hosted-runner/current" ]; then
  target=$(readlink -f /home/akushnir/self-hosted-runner/current)
  if [ -f "$target/release-content.txt" ]; then
    echo "SBOM integration test passed"
    exit 0
  else
    echo "Artifact missing in release dir" >&2
    exit 2
  fi
else
  echo "current symlink not created" >&2
  exit 3
fi
