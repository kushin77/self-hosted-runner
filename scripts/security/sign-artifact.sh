#!/usr/bin/env bash
# Sign a file with GPG. Usage: ./sign-artifact.sh <file>

if [ $# -ne 1 ]; then
  echo "Usage: $0 <file>" >&2
  exit 1
fi

file=$1

if ! command -v gpg >/dev/null 2>&1; then
  echo "gpg not installed" >&2
  exit 1
fi

gpg --armor --detach-sign "$file"

echo "Created signature ${file}.asc"