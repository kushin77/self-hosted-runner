#!/usr/bin/env bash
set -euo pipefail

# pin-base-images.sh
# Usage: ./scripts/pin-base-images.sh path/to/Dockerfile [path/to/OtherDockerfile ...]
# This script pulls the base image referenced on the first FROM line and replaces
# the tag with the resolved digest (image@sha256:...). Requires Docker CLI and network access.

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 Dockerfile [Dockerfile2 ...]"
  exit 2
fi

for df in "$@"; do
  if [ ! -f "$df" ]; then
    echo "Skipping missing file: $df"
    continue
  fi

  # Read first FROM line (handles AS aliases)
  from_line=$(grep -m1 -E '^FROM ' "$df" || true)
  if [ -z "$from_line" ]; then
    echo "No FROM line found in $df; skipping"
    continue
  fi

  # Extract image (could be 'node:20-alpine' or 'node:20' etc.)
  image_tag=$(echo "$from_line" | awk '{print $2}')

  # Export ARGs defined earlier in the Dockerfile so we can expand variables in FROM
  # Read ARG lines up to the FROM line and export them for expansion
  # Collect ARG assignments (with defaults) prior to the FROM line into a temp file
  tmpfile=$(mktemp)
  awk '/^FROM /{exit} /^ARG /{print}' "$df" | sed 's/^ARG //' | grep '=' > "$tmpfile" || true
  if [ -s "$tmpfile" ]; then
    # Export variables from tmpfile into the current shell
    set -a
    # shellcheck disable=SC1090
    . "$tmpfile"
    set +a
  fi
  rm -f "$tmpfile"

  # Expand any variable references in the image tag (e.g., ${NODE_VERSION})
  expanded_image_tag=$(eval "echo $image_tag")
  if [ -n "$expanded_image_tag" ]; then
    image_tag="$expanded_image_tag"
  fi
  echo "Processing $df -> base image: $image_tag"

  echo "Pulling $image_tag..."
  docker pull "$image_tag"

  # Get first RepoDigest from inspect
  repo_digest=$(docker inspect --format='{{index .RepoDigests 0}}' "$image_tag" 2>/dev/null || true)
  if [ -z "$repo_digest" ]; then
    echo "Could not resolve digest for $image_tag; skipping $df"
    continue
  fi

  echo "Resolved digest: $repo_digest"

  # repo_digest can be like 'node@sha256:abc123' or 'registry/repo@sha256:...'
  # Replace the FROM line to use the digest
  # Preserve any AS alias
  alias_part=$(echo "$from_line" | awk '{if (NF>2) {for (i=3;i<=NF;i++) printf " %s", $i}}')
  new_from="FROM $repo_digest$alias_part"

  # Use a temp file to replace only the first occurrence
  awk -v old="$from_line" -v new="$new_from" 'BEGIN{n=0} { if(n==0 && $0==old){print new; n=1} else print $0 }' "$df" > "$df.tmp" && mv "$df.tmp" "$df"

  echo "Updated $df: $from_line -> $new_from"
done

echo "Done. Review changes and commit them."
