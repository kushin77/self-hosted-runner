#!/usr/bin/env bash
##
## Cosign Artifact Signing
## Signs container images and attestations using Cosign.
##
set -euo pipefail

ARTIFACT="${1}"
COSIGN_KEY="${COSIGN_KEY:-}"
COSIGN_PASSWORD="${COSIGN_PASSWORD:-}"

if [ -z "${ARTIFACT}" ]; then
  echo "Usage: $0 <image:tag>"
  exit 1
fi

echo "Signing artifact: ${ARTIFACT}"

# Install cosign if missing
if ! command -v cosign &>/dev/null; then
  echo "Installing cosign..."
  wget -qO /usr/local/bin/cosign https://github.com/sigstore/cosign/releases/download/v2.0.0/cosign-linux-amd64
  chmod +x /usr/local/bin/cosign
fi

# Sign with keyfile
if [ -n "${COSIGN_KEY}" ] && [ -f "${COSIGN_KEY}" ]; then
  echo "Signing with keyfile..."
  export COSIGN_PASSWORD
  
  cosign sign --key "${COSIGN_KEY}" "${ARTIFACT}"
  
  echo "✓ Image signed with cosign (keyfile)"
fi

# Sign with Keyless (Sigstore OIDC)
if command -v cosign &>/dev/null && [ -z "${COSIGN_KEY}" ]; then
  echo "Signing with Keyless (Sigstore)..."
  
  cosign sign --keyless \
    "${ARTIFACT}" \
    2>&1 | tee -a /dev/stderr
  
  echo "✓ Image signed with Keyless"
fi

# Verify signature
echo "Verifying signature..."
if [ -n "${COSIGN_KEY}" ]; then
  cosign verify --key "${COSIGN_KEY}.pub" "${ARTIFACT}"
else
  cosign verify --keyless "${ARTIFACT}"
fi

echo "✓ Signature verified"

# Generate attestation (SLSA provenance)
echo "Generating SLSA attestation..."
cat > /tmp/provenance.json <<EOF
{
  "_type": "https://in-toto.io/Statement/v0.1",
  "predicateType": "https://slsa.dev/provenance/v0.2",
  "subject": [
    {
      "name": "${ARTIFACT}",
      "digest": {
        "sha256": "$(cosign triangulate ${ARTIFACT} | jq -r '.spec.imageID | split(\"@\")[1]')"
      }
    }
  ],
  "predicate": {
    "buildType": "https://github.com/slsa-framework/slsa-github-generator/release/workflows/builder",
    "builder": {
      "id": "https://github.com/slsa-framework/slsa-github-generator/releases/tag/v1.0.0"
    },
    "invocation": {
      "configSource": {
        "uri": "$(git config --get remote.origin.url)",
        "digest": {
          "sha1": "$(git rev-parse HEAD)"
        }
      }
    },
    "buildConfig": {},
    "materials": [],
    "startedOn": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
    "finishedOn": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  }
}
EOF

# Attach attestation with cosign
cosign attach attestation --attestation /tmp/provenance.json "${ARTIFACT}"

echo "✓ Attestation attached"
