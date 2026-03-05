#!/bin/sh
set -eu

echo "Running self-update atomic apply smoke test"

mkdir -p tests/artifacts
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

echo "fake-release" > "$tmpdir/release-content.txt"
tar -czf tests/artifacts/fake-art.tar.gz -C "$tmpdir" release-content.txt

ARTIFACT_PATH="$(pwd)/tests/artifacts/fake-art.tar.gz"

# Ensure releases dir is clean
rm -rf /home/akushnir/self-hosted-runner/releases || true
mkdir -p /home/akushnir/self-hosted-runner/releases

sh self-update/apply-update.sh --current self-update/version --artifact-url "$ARTIFACT_PATH" --no-service

if [ -L "/home/akushnir/self-hosted-runner/current" ]; then
  target=$(readlink -f /home/akushnir/self-hosted-runner/current)
  echo "Current link points to: $target"
  if [ -f "$target/release-content.txt" ]; then
    echo "Artifact present in release dir"
    echo "self-update atomic apply smoke test passed"
    exit 0
  else
    echo "release content missing" >&2
    exit 2
  fi
else
  echo "current symlink not created" >&2
  exit 3
fi
