#!/usr/bin/env bash
set -euo pipefail

# staging_signing_validate.sh
# Lightweight staging validation for signing workflow. Will attempt to
# - create a small test artifact
# - fetch signing key from GSM if _SIGNING_SECRET_NAME is provided
# - sign artifact (using scripts/signing/sign_artifact.sh)
# - optionally verify signature using provided public key path (PUBLIC_KEY_PATH)

ARTIFACT=${1:-"build/test-artifact.bin"}
SIGN_KEY_PATH=${2:-""}
PUBLIC_KEY_PATH=${3:-""}

mkdir -p $(dirname "$ARTIFACT")
echo "test-signing-$(date +%s)" > "$ARTIFACT"

if [ -z "$SIGN_KEY_PATH" ]; then
  if [ -n "${_SIGNING_SECRET_NAME:-}" ]; then
    echo "Fetching signing key from GSM: ${_SIGNING_SECRET_NAME}"
    gcloud secrets versions access latest --secret="${_SIGNING_SECRET_NAME}" > signing_key.pem
    SIGN_KEY_PATH=signing_key.pem
    chmod 600 "$SIGN_KEY_PATH"
  else
    echo "No signing key provided and _SIGNING_SECRET_NAME not set. Skipping signing validation." >&2
    exit 0
  fi
fi

if [ ! -x scripts/signing/sign_artifact.sh ]; then
  chmod +x scripts/signing/sign_artifact.sh || true
fi

echo "Signing artifact with $SIGN_KEY_PATH"
scripts/signing/sign_artifact.sh "$SIGN_KEY_PATH" "$ARTIFACT"

if [ -n "$PUBLIC_KEY_PATH" ] && [ -f "$PUBLIC_KEY_PATH" ]; then
  echo "Verifying signature with $PUBLIC_KEY_PATH"
  if command -v openssl >/dev/null 2>&1; then
    openssl pkeyutl -verify -pubin -inkey "$PUBLIC_KEY_PATH" -in "$ARTIFACT" -sigfile "${ARTIFACT}.sig" && echo "Signature OK"
  else
    echo "openssl not available; skipping verification"
  fi
else
  echo "No public key provided; verification skipped"
fi

echo "Staging signing validation finished. Signature: ${ARTIFACT}.sig"
