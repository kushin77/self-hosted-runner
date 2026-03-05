#!/bin/sh
set -eu

echo "Running cosign verification behavior test"

if [ ! -f "self-update/apply-update.sh" ]; then
  echo "apply-update.sh missing" >&2
  exit 2
fi

# Run apply-update in dry-run mode; script should handle absence of cosign gracefully
sh self-update/apply-update.sh --current self-update/version --artifact-url https://example.com/art.tar.gz --dry-run

echo "cosign behavior test passed (script handles missing cosign)"
exit 0
