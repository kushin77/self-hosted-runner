#!/usr/bin/env bash
set -euo pipefail

# Pull images listed in a manifest and save them as tarballs for air-gapped import.
# Usage: ./preload_images.sh [manifest.yml] [output-dir]

MANIFEST=${1:-deploy/airgap/manifest.yml}
OUTDIR=${2:-build/airgap-images}
mkdir -p "$OUTDIR"

if [ ! -f "$MANIFEST" ]; then
  echo "Manifest not found: $MANIFEST"
  echo "Generate one with scripts/airgap/generate_image_manifest.sh > $MANIFEST"
  exit 1
fi

images=$(grep -E "^\s*image:\s*" -h "$MANIFEST" | sed -E 's/^[[:space:]]*image:[[:space:]]*//')

for img in $images; do
  echo "Pulling $img"
  docker pull "$img"
  name=$(echo "$img" | sed -E 's/[:\/]/_/g')
  tarfile="$OUTDIR/${name}.tar"
  echo "Saving $img -> $tarfile"
  docker save -o "$tarfile" "$img"
done

echo "Saved $(ls -1 "$OUTDIR"/*.tar 2>/dev/null | wc -l) images to $OUTDIR"
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