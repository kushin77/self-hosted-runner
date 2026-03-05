#!/usr/bin/env bash
set -euo pipefail

# preload_images.sh
# Pulls container images and saves them as tarballs for air-gapped transport.
# Usage: preload_images.sh images.txt output_dir

IMAGES_FILE=${1:-}
OUT_DIR=${2:-./images}

if [[ -z "$IMAGES_FILE" || ! -f "$IMAGES_FILE" ]]; then
  echo "Usage: $0 images.txt [output_dir]"
  echo "images.txt should contain one image per line, e.g. quay.io/otel/opentelemetry-collector-contrib:0.58.0"
  exit 2
fi

mkdir -p "$OUT_DIR"

while IFS= read -r image; do
  image=$(echo "$image" | sed 's/^\s\+//;s/\s\+$//')
  [[ -z "$image" || "$image" =~ ^# ]] && continue
  echo "Pulling $image..."
  if command -v docker >/dev/null 2>&1; then
    docker pull "$image"
    fname="$(echo "$image" | sed 's/[:\/]/_/g').tar"
    echo "Saving to $OUT_DIR/$fname"
    docker save -o "$OUT_DIR/$fname" "$image"
  elif command -v podman >/dev/null 2>&1; then
    podman pull "$image"
    fname="$(echo "$image" | sed 's/[:\/]/_/g').tar"
    podman save -o "$OUT_DIR/$fname" "$image"
  else
    echo "Neither docker nor podman found; install one to run this script." >&2
    exit 1
  fi
done < "$IMAGES_FILE"

echo "Saved images to $OUT_DIR"