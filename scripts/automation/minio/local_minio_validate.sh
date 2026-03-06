#!/usr/bin/env bash
set -euo pipefail

# Local MinIO smoke-test helper
# Runs a MinIO container, configures mc, creates bucket, uploads and downloads a test object

MINIO_USER=${MINIO_ROOT_USER:-minioadmin}
MINIO_PASS=${MINIO_ROOT_PASSWORD:-minioadmin}
MINIO_PORT=${MINIO_PORT:-9000}
BUCKET=${MINIO_BUCKET:-test-bucket}
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

echo "Starting local MinIO smoke-test..."

docker pull minio/minio:latest
CONTAINER_ID=$(docker run -d --rm -p ${MINIO_PORT}:9000 -p 9001:9001 -e MINIO_ROOT_USER=${MINIO_USER} -e MINIO_ROOT_PASSWORD=${MINIO_PASS} minio/minio server /data --console-address ":9001")

echo "MinIO container started: $CONTAINER_ID"

# Wait for MinIO to be ready
for i in {1..30}; do
  if curl -sS http://127.0.0.1:${MINIO_PORT}/minio/health/live >/dev/null 2>&1; then
    echo "MinIO ready"
    break
  fi
  echo "Waiting for MinIO (${i}/30)..."
  sleep 1
done

# Install mc (MinIO client)
MC_BIN=/usr/local/bin/mc
if [ ! -x "$MC_BIN" ]; then
  echo "Installing mc client..."
  curl -sSfL https://dl.min.io/client/mc/release/linux-amd64/mc -o /tmp/mc
  chmod +x /tmp/mc
  sudo mv /tmp/mc $MC_BIN
fi

# Configure mc
mc alias set local http://127.0.0.1:${MINIO_PORT} ${MINIO_USER} ${MINIO_PASS} --api S3v4

# Create bucket
mc mb --ignore-existing local/${BUCKET}

# Upload test object
echo "hello-minio" > /tmp/minio_test_object.txt
mc cp /tmp/minio_test_object.txt local/${BUCKET}/minio_test_object.txt

# Download and verify
mc cp local/${BUCKET}/minio_test_object.txt /tmp/minio_test_object_downloaded.txt
if grep -q "hello-minio" /tmp/minio_test_object_downloaded.txt; then
  echo "MinIO smoke-test PASS"
  RESULT=0
else
  echo "MinIO smoke-test FAIL"
  RESULT=2
fi

# Cleanup
docker stop $CONTAINER_ID >/dev/null || true

exit $RESULT
