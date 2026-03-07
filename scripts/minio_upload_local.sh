#!/usr/bin/env bash
set -euo pipefail

# Upload a GitHub release asset to an S3/MinIO-compatible endpoint from a
# machine that has network access to the target endpoint.
#
# Usage:
#   MINIO_ENDPOINT=https://minio.example:9000 MINIO_ACCESS_KEY=key \
#     MINIO_SECRET_KEY=secret MINIO_BUCKET=bucket ./scripts/minio_upload_local.sh \
#     --tag ph3-artifacts-20260307000413 --asset phase3_artifacts_20260307_000055.tar.gz 
#
# Or provide arguments interactively:
#   ./scripts/minio_upload_local.sh --url https://github.com/.../phase3.tar.gz \
#     --endpoint https://minio:9000 --access-key KEY --secret-key SECRET --bucket my-bucket --object "phase3/phase3.tar.gz"

usage(){
  grep '^#' "$0" | sed -n '1,120p' >&2
}

TAG=""
ASSET=""
URL=""
ENDPOINT="${MINIO_ENDPOINT:-}"
ACCESS_KEY="${MINIO_ACCESS_KEY:-}"
SECRET_KEY="${MINIO_SECRET_KEY:-}"
BUCKET="${MINIO_BUCKET:-}"
OBJECT_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag) TAG="$2"; shift 2;;
    --asset) ASSET="$2"; shift 2;;
    --url) URL="$2"; shift 2;;
    --endpoint) ENDPOINT="$2"; shift 2;;
    --access-key) ACCESS_KEY="$2"; shift 2;;
    --secret-key) SECRET_KEY="$2"; shift 2;;
    --bucket) BUCKET="$2"; shift 2;;
    --object) OBJECT_PATH="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2;;
  esac
done

if [[ -z "$URL" ]]; then
  if [[ -n "$TAG" && -n "$ASSET" ]]; then
    echo "Downloading release asset $ASSET from tag $TAG" >&2
    gh release download "$TAG" --pattern "$ASSET" --repo kushin77/self-hosted-runner
    URL="$ASSET"
  else
    echo "Either --url or both --tag and --asset are required" >&2
    usage; exit 2
  fi
fi

if [[ -z "$ENDPOINT" || -z "$ACCESS_KEY" || -z "$SECRET_KEY" || -z "$BUCKET" || -z "$OBJECT_PATH" ]]; then
  echo "MINIO_ENDPOINT, MINIO_ACCESS_KEY, MINIO_SECRET_KEY, MINIO_BUCKET and object path are required either via env or flags" >&2
  usage; exit 2
fi

echo "Preparing to upload $URL -> $ENDPOINT/$BUCKET/$OBJECT_PATH" >&2

# ensure mc installed locally
if ! command -v mc >/dev/null 2>&1; then
  echo "mc not found, installing temporary mc binary" >&2
  TMPBIN="/tmp/mc-$$"
  curl -fsSL https://dl.min.io/client/mc/release/linux-amd64/mc -o "$TMPBIN"
  chmod +x "$TMPBIN"
  MC_BIN="$TMPBIN"
else
  MC_BIN="$(command -v mc)"
fi

echo "Setting mc alias" >&2
"$MC_BIN" alias set tmp-minio "$ENDPOINT" "$ACCESS_KEY" "$SECRET_KEY" --api S3v4

echo "Creating bucket if absent" >&2
"$MC_BIN" mb --ignore-existing tmp-minio/"$BUCKET"

echo "Uploading $URL to tmp-minio/$BUCKET/$OBJECT_PATH" >&2
"$MC_BIN" cp "$URL" tmp-minio/"$BUCKET"/"$OBJECT_PATH"

echo "Upload complete. MinIO URL: ${ENDPOINT%/}/${BUCKET}/${OBJECT_PATH}" >&2

if [[ -n "${TMPBIN:-}" && -f "$TMPBIN" ]]; then
  rm -f "$TMPBIN"
fi

exit 0
