#!/usr/bin/env bash
set -euo pipefail

mkdir -p build/provenance

PROV_FILE=build/provenance/sample-provenance.json

cat > "$PROV_FILE" <<EOF
{
  "provenance": {
    "builder": "sample-ci",
    "buildType": "example/build",
    "source": {
      "type": "git",
      "url": "https://github.com/example/repo",
      "commit": "0000000000000000000000000000000000000000"
    }
  }
}
EOF

echo "✓ Provenance generated: $PROV_FILE"
