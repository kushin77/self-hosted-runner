#!/usr/bin/env bash
set -euo pipefail

# fetch-runner-binaries.sh
# Minimal fetcher for runner binaries referenced in this repo.
# Usage: SCRIPTS should provide a URL list via RUNNER_ASSET_URLS (newline-separated)
# Or provide RUNNER_RELEASE_OWNER, RUNNER_RELEASE_REPO and TAG to download assets from GitHub releases.

OUT_DIR="artifacts/runners"
mkdir -p "$OUT_DIR"

if [ -n "${RUNNER_ASSET_URLS:-}" ]; then
  echo "Fetching runner assets from RUNNER_ASSET_URLS"
  echo "$RUNNER_ASSET_URLS" | while IFS= read -r url; do
    [ -z "$url" ] && continue
    file=$(basename "$url")
    echo "Downloading $url -> $OUT_DIR/$file"
    curl -fsSL "$url" -o "$OUT_DIR/$file"
    chmod +x "$OUT_DIR/$file" || true
  done
  exit 0
fi

# If GitHub release info provided, download assets for the release tag
if [ -n "${RUNNER_RELEASE_OWNER:-}" ] && [ -n "${RUNNER_RELEASE_REPO:-}" ] && [ -n "${RUNNER_RELEASE_TAG:-}" ]; then
  echo "Fetching assets from GitHub release ${RUNNER_RELEASE_OWNER}/${RUNNER_RELEASE_REPO}@${RUNNER_RELEASE_TAG}"
  api_url="https://api.github.com/repos/${RUNNER_RELEASE_OWNER}/${RUNNER_RELEASE_REPO}/releases/tags/${RUNNER_RELEASE_TAG}"
  assets=$(curl -fsSL "$api_url" | jq -r '.assets[] | .browser_download_url')
  for url in $assets; do
    file=$(basename "$url")
    echo "Downloading $url -> $OUT_DIR/$file"
    curl -fsSL "$url" -o "$OUT_DIR/$file"
    chmod +x "$OUT_DIR/$file" || true
  done
  exit 0
fi

cat <<EOF
No RUNNER_ASSET_URLS or release info provided.
Provide either:
- RUNNER_ASSET_URLS (newline-separated URLs)
or
- RUNNER_RELEASE_OWNER, RUNNER_RELEASE_REPO, RUNNER_RELEASE_TAG (will download all release assets)
EOF
exit 1
