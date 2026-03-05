#!/bin/sh
set -eu

echo "Running self-update cosign integration test (uses fake cosign)"

tmpbin=$(mktemp -d)
trap 'rm -rf "$tmpbin"' EXIT

# Create fake cosign that accepts verify-blob and returns success
cat > "$tmpbin/cosign" <<'EOF'
#!/bin/sh
if [ "$1" = "verify-blob" ]; then
  # simulate success
  exit 0
fi
exit 2
EOF
chmod +x "$tmpbin/cosign"

export PATH="$tmpbin:$PATH"

mkdir -p tests/artifacts
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
echo "fake-release" > "$tmpdir/release-content.txt"
tar -czf tests/artifacts/fake-art-cosign.tar.gz -C "$tmpdir" release-content.txt

ARTIFACT_PATH="$(pwd)/tests/artifacts/fake-art-cosign.tar.gz"

rm -rf /home/akushnir/self-hosted-runner/releases || true
mkdir -p /home/akushnir/self-hosted-runner/releases

export COSIGN_KEY="dummy-key"
export COSIGN_REQUIRED=1

# Run apply-update in no-service mode so it doesn't try to manage systemd
sh self-update/apply-update.sh --current self-update/version --artifact-url "$ARTIFACT_PATH" --no-service

if [ -L "/home/akushnir/self-hosted-runner/current" ]; then
  echo "cosign integration test: current symlink created"
  exit 0
else
  echo "cosign integration test: failed to create symlink" >&2
  exit 2
fi
