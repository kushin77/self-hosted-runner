#!/usr/bin/env bash
set -euo pipefail

# sign_artifact.sh
# Simple wrapper to sign a file using an Ed25519 private key (PEM).
# Expects: SIGN_KEY_PATH environment variable or first arg, artifact path as second arg.

usage() {
  echo "Usage: $0 <private-key-pem> <artifact-path> [signature-output]"
  exit 2
}

if [ "$#" -lt 2 ]; then
  usage
fi

KEY_PATH="$1"
ARTIFACT="$2"
SIG_OUT="${3:-${ARTIFACT}.sig}"

if [ ! -f "$KEY_PATH" ]; then
  echo "Private key not found: $KEY_PATH" >&2
  exit 3
fi

if [ ! -f "$ARTIFACT" ]; then
  echo "Artifact not found: $ARTIFACT" >&2
  exit 4
fi

echo "Signing $ARTIFACT -> $SIG_OUT using $KEY_PATH"

# Prefer ssh-keygen (OpenSSH -Y sign, recommended for Ed25519)
if command -v ssh-keygen >/dev/null 2>&1; then
  if ssh-keygen -Y sign -f "$KEY_PATH" -n artifact < "$ARTIFACT" > "$SIG_OUT" 2>/dev/null; then
    echo "Signed with ssh-keygen -> $SIG_OUT"
    exit 0
  else
    echo "ssh-keygen sign failed or produced no signature; falling back to openssl" >&2
  fi
fi

# Fallback: try OpenSSL for signing (may not support Ed25519 on all versions)
if command -v openssl >/dev/null 2>&1; then
  openssl pkeyutl -inkey "$KEY_PATH" -sign -in "$ARTIFACT" -out "$SIG_OUT" && {
    echo "Signed with openssl -> $SIG_OUT"
    exit 0
  } || {
    echo "OpenSSL signing failed for this key type" >&2
  }
fi

echo "No supported signing tool succeeded (ssh-keygen or openssl required)" >&2
exit 6
