#!/usr/bin/env bash
set -euo pipefail

# create_sealedsecret_from_token.sh
# Create a Kubernetes Secret manifest (or SealedSecret if `kubeseal` is available)
# Usage: ./scripts/ci/create_sealedsecret_from_token.sh <REG_TOKEN> [NAMESPACE]

REG_TOKEN=${1:-}
NAMESPACE=${2:-gitlab-runner}

if [ -z "$REG_TOKEN" ]; then
  echo "Usage: $0 <REG_TOKEN> [NAMESPACE]"
  exit 1
fi

TMP_SECRET=$(mktemp /tmp/gitlab-regtoken.XXXX.yaml)
cat > "$TMP_SECRET" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: gitlab-runner-regtoken
  namespace: ${NAMESPACE}
type: Opaque
data:
  registrationToken: $(echo -n "$REG_TOKEN" | base64 -w0)
EOF

if command -v kubeseal >/dev/null 2>&1; then
  echo "kubeseal found — generating SealedSecret (cluster public key required)"
  mkdir -p infra/gitlab-runner
  kubeseal --format yaml < "$TMP_SECRET" > infra/gitlab-runner/sealedsecret.generated.yaml
  echo "Wrote infra/gitlab-runner/sealedsecret.generated.yaml — apply this to the cluster where the SealedSecrets controller is installed."
  rm -f "$TMP_SECRET"
  echo "Done."
else
  echo "kubeseal not found — writing plain Secret manifest to infra/gitlab-runner/secret.generated.yaml"
  mkdir -p infra/gitlab-runner
  mv "$TMP_SECRET" infra/gitlab-runner/secret.generated.yaml
  echo "Wrote infra/gitlab-runner/secret.generated.yaml — apply it with 'kubectl apply -f' when ready."
fi

echo "Remember: do NOT commit real tokens into Git. Use SealedSecrets or ExternalSecrets in CI." 
