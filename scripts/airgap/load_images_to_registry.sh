#!/usr/bin/env bash
set -euo pipefail

# Load tarballs produced by preload_images.sh and push them to a target registry.
# Usage: ./load_images_to_registry.sh <registry> <images-dir>

REGISTRY=${1:?Please provide target registry (e.g. my-registry.local:5000)}
IMAGEDIR=${2:-build/airgap-images}

if [ ! -d "$IMAGEDIR" ]; then
  echo "Images directory not found: $IMAGEDIR"
  exit 1
fi

for tar in "$IMAGEDIR"/*.tar; do
  [ -e "$tar" ] || continue
  echo "Loading $tar"
  img=$(docker load -i "$tar" | sed -n 's/Loaded image: //p')
  if [ -z "$img" ]; then
    # Fallback to parsing repo:tag from docker load output
    img=$(docker load -i "$tar" | tail -n1 | awk '{print $3}')
  fi
  echo "Tagging $img -> $REGISTRY/$img"
  docker tag "$img" "$REGISTRY/$img"
  echo "Pushing $REGISTRY/$img"
  docker push "$REGISTRY/$img"
done

echo "Done pushing images to $REGISTRY"
#!/usr/bin/env bash
set -euo pipefail

# load_images_to_registry.sh
# Loads image tarballs into a container runtime and pushes them to a target registry.
# Usage: load_images_to_registry.sh /path/to/tarballs target-registry[:port]

TARBALL_DIR=${1:-}
TARGET_REGISTRY=${2:-}

if [[ -z "$TARBALL_DIR" || -z "$TARGET_REGISTRY" ]]; then
  echo "Usage: $0 /path/to/tarballs target-registry[:port]"
  exit 2
fi

if [[ ! -d "$TARBALL_DIR" ]]; then
  echo "Directory not found: $TARBALL_DIR" >&2
  exit 1
fi

if command -v docker >/dev/null 2>&1; then
  RUNTIME=docker
elif command -v podman >/dev/null 2>&1; then
  RUNTIME=podman
else
  echo "Neither docker nor podman found; install one to run this script." >&2
  exit 1
fi

for f in "$TARBALL_DIR"/*.tar "$TARBALL_DIR"/*.tar.gz; do
  [[ -e "$f" ]] || continue
  echo "Loading $f"
  if [[ "$RUNTIME" = "docker" ]]; then
    docker load -i "$f"
  else
    podman load -i "$f"
  fi
  # attempt to discover images loaded by inspecting tar metadata (best-effort)
  images=$(tar -tf "$f" | grep -E "manifest.json$" >/dev/null && tar -xOf "$f" manifest.json | jq -r '.[0].RepoTags[]' 2>/dev/null || true)
  if [[ -z "$images" ]]; then
    echo "Could not determine image names from $f; please tag and push manually if needed."
    continue
  fi
  for img in $images; do
    # re-tag for target registry
    name=$(echo "$img" | sed 's@.*/@@')
    target="$TARGET_REGISTRY/$name"
    echo "Tagging $img -> $target"
    $RUNTIME tag "$img" "$target"
    echo "Pushing $target"
    $RUNTIME push "$target"
  done
done

echo "Done loading and pushing images to $TARGET_REGISTRY"