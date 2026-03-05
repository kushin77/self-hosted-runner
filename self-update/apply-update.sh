#!/bin/sh
# Placeholder self-update apply script. Performs a dry-run or a simulated update.
# Usage: apply-update.sh --current <file> [--artifact-url <url>] [--dry-run]

set -eu

current_file=""
artifact_url=""
dry_run=0
NO_SERVICE=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --current) current_file="$2"; shift 2 ;;
    --artifact-url) artifact_url="$2"; shift 2 ;;
    --dry-run) dry_run=1; shift 1 ;;
    --no-service) NO_SERVICE=1; shift 1 ;;
    --help) echo "Usage: $0 --current <file> [--artifact-url <url>] [--dry-run] [--no-service]"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$current_file" ]; then
  echo "--current <file> required" >&2
  exit 2
fi

if [ ! -f "$current_file" ]; then
  echo "current file not found: $current_file" >&2
  exit 3
fi

current_version=$(cat "$current_file" | tr -d '\n' || true)

echo "current version: $current_version"

# ENV/flags
# If COSIGN_REQUIRED=1, verification with cosign is mandatory.
COSIGN_REQUIRED=${COSIGN_REQUIRED:-0}
SBOM_URL=${SBOM_URL:-}
RELEASES_DIR=${RELEASES_DIR:-/home/akushnir/self-hosted-runner/releases}
CURRENT_LINK=${CURRENT_LINK:-/home/akushnir/self-hosted-runner/current}

if [ "$dry_run" -eq 1 ]; then
  echo "Dry run: would fetch artifact from: ${artifact_url:-<none>}"
  if [ -n "$SBOM_URL" ]; then
    echo "Dry run: would fetch SBOM from: $SBOM_URL"
  fi
  echo "Dry run: would verify signature (cosign if present) and perform atomic apply"
  exit 0
fi

if [ -f /proc/1/comm ] && grep -q systemd /proc/1/comm 2>/dev/null; then
  SYSTEM_HAS_SYSTEMD=1
else
  SYSTEM_HAS_SYSTEMD=0
fi

echo "Fetching artifact from: ${artifact_url:-<none>}"
if [ -z "$artifact_url" ]; then
  echo "No artifact URL provided; nothing to do" >&2
  exit 6
fi

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

artifact_path="$tmpdir/artifact"

# Support local file paths and remote URLs
if [ -f "$artifact_url" ]; then
  cp "$artifact_url" "$artifact_path" || { echo "failed to copy local artifact" >&2; exit 4; }
elif echo "$artifact_url" | grep -qE '^file://'; then
  path=$(echo "$artifact_url" | sed 's|^file://||')
  cp "$path" "$artifact_path" || { echo "failed to copy file:// artifact" >&2; exit 4; }
elif command -v curl >/dev/null 2>&1; then
  curl -fsS -o "$artifact_path" "$artifact_url" || { echo "failed to fetch artifact" >&2; exit 4; }
elif command -v wget >/dev/null 2>&1; then
  wget -qO "$artifact_path" "$artifact_url" || { echo "failed to fetch artifact" >&2; exit 4; }
else
  echo "No HTTP client available to fetch artifact" >&2
  exit 5
fi

echo "Fetched artifact to $artifact_path"

# Fetch SBOM if provided
sbom_path=""
if [ -n "$SBOM_URL" ]; then
  sbom_path="$tmpdir/artifact.sbom"
  if [ -f "$SBOM_URL" ]; then
    cp "$SBOM_URL" "$sbom_path" || { echo "failed to copy local sbom" >&2; exit 7; }
  elif echo "$SBOM_URL" | grep -qE '^file://'; then
    path=$(echo "$SBOM_URL" | sed 's|^file://||')
    cp "$path" "$sbom_path" || { echo "failed to copy file:// sbom" >&2; exit 7; }
  elif command -v curl >/dev/null 2>&1; then
    curl -fsS -o "$sbom_path" "$SBOM_URL" || { echo "failed to fetch sbom" >&2; exit 7; }
  fi
  echo "Fetched SBOM to $sbom_path"
fi

# Verify signature with cosign when present or required
# Verify signature with cosign when present or required
if command -v cosign >/dev/null 2>&1; then
  echo "Verifying artifact signature with cosign"
  # Prefer verify-blob (cosign v1+ supports verify-blob). If COSIGN_KEY is set, use it.
  if [ -n "${COSIGN_KEY:-}" ]; then
    if cosign verify-blob --key "$COSIGN_KEY" "$artifact_path" >/dev/null 2>&1; then
      echo "cosign verify-blob succeeded"
    else
      echo "cosign verify-blob failed" >&2
      if [ "$COSIGN_REQUIRED" -eq 1 ]; then
        exit 8
      fi
    fi
  else
    if [ "${COSIGN_KEYLESS:-0}" -eq 1 ]; then
      if cosign verify-blob --keyless "$artifact_path" >/dev/null 2>&1; then
        echo "cosign keyless verify-blob succeeded"
      else
        echo "cosign keyless verify-blob failed" >&2
        if [ "$COSIGN_REQUIRED" -eq 1 ]; then
          exit 8
        fi
      fi
    else
      echo "No COSIGN_KEY provided and keyless not requested; skipping cosign verification" >&2
    fi
  fi
else
  if [ "$COSIGN_REQUIRED" -eq 1 ]; then
    echo "cosign required but not installed; aborting" >&2
    exit 8
  else
    echo "cosign not installed; continuing (not required)" >&2
  fi
fi

# Prepare releases directory
mkdir -p "$RELEASES_DIR"
release_name="release-$(date -u +%Y%m%dT%H%M%SZ)"
release_dir="$RELEASES_DIR/$release_name"
mkdir -p "$release_dir"

# If artifact is a tarball, extract; otherwise copy
if file "$artifact_path" | grep -q 'gzip compressed data'; then
  if command -v tar >/dev/null 2>&1; then
    tar -xzf "$artifact_path" -C "$release_dir" || { echo "failed to extract artifact" >&2; rm -rf "$release_dir"; exit 9; }
  else
    echo "tar not available to extract artifact" >&2
    rm -rf "$release_dir"
    exit 10
  fi
else
  # copy as-is
  cp "$artifact_path" "$release_dir/" || { echo "failed to copy artifact into release dir" >&2; rm -rf "$release_dir"; exit 11; }
fi

# Place a version token in the release for traceability
echo "$current_version -> $(date -u +%Y%m%dT%H%M%SZ)" > "$release_dir/DEPLOYED_FROM"

# Basic SBOM validation: if SBOM provided, ensure non-empty and contains recognizable fields
if [ -n "$sbom_path" ]; then
  if [ -s "$sbom_path" ]; then
    if grep -qiE 'syft|spdx|cyclonedx|package' "$sbom_path" >/dev/null 2>&1; then
      echo "SBOM looks present and valid"
      cp "$sbom_path" "$release_dir/SBOM.json" || true
    else
      echo "SBOM fetched but content did not appear valid" >&2
      if [ "${SBOM_REQUIRED:-0}" -eq 1 ]; then
        echo "SBOM is required; aborting" >&2
        rm -rf "$release_dir"
        exit 14
      else
        echo "SBOM not required; continuing" >&2
      fi
    fi
  else
    echo "SBOM fetch resulted in empty file" >&2
    if [ "${SBOM_REQUIRED:-0}" -eq 1 ]; then
      echo "SBOM required; aborting" >&2
      rm -rf "$release_dir"
      exit 15
    fi
  fi
fi

# Atomic symlink swap
prev_target=""
if [ -L "$CURRENT_LINK" ]; then
  prev_target=$(readlink -f "$CURRENT_LINK" || true)
fi

ln -sfn "$release_dir" "$CURRENT_LINK"
echo "Swapped current link to $release_dir"

# Optionally manage service and health-check
if [ "$NO_SERVICE" -eq 1 ]; then
  echo "NO_SERVICE=1 set; skipping service restart and health-check"
  echo "Update applied to $release_dir"
  exit 0
fi

echo "Restarting runner service"
if [ "$SYSTEM_HAS_SYSTEMD" -eq 1 ] && command -v systemctl >/dev/null 2>&1; then
  systemctl restart runner.service || true
fi

# Run health-check script if present
if [ -x "/home/akushnir/self-hosted-runner/self-update/health-check.sh" ]; then
  echo "Running health-check.sh"
  if /home/akushnir/self-hosted-runner/self-update/health-check.sh; then
    echo "Health-check passed"
    exit 0
  else
    echo "Health-check failed; rolling back"
    if [ -n "$prev_target" ]; then
      ln -sfn "$prev_target" "$CURRENT_LINK"
      if [ "$SYSTEM_HAS_SYSTEMD" -eq 1 ] && command -v systemctl >/dev/null 2>&1; then
        systemctl restart runner.service || true
      fi
    fi
    echo "Rolled back to $prev_target"
    exit 12
  fi
else
  # Basic check: if systemctl present, ensure runner.service is active
  if [ "$SYSTEM_HAS_SYSTEMD" -eq 1 ] && command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active --quiet runner.service; then
      echo "runner.service active; update successful"
      exit 0
    else
      echo "runner.service not active after restart; rolling back"
      if [ -n "$prev_target" ]; then
        ln -sfn "$prev_target" "$CURRENT_LINK"
        systemctl restart runner.service || true
      fi
      exit 13
    fi
  else
    echo "No health-check available; assuming success"
    exit 0
  fi
fi
