#!/usr/bin/env bash
# Runner OIDC deploy helper
# Installs minimal config for a self-hosted runner to use Workload Identity Federation
# Assumes Workload Identity Pool and Provider exist and service account 'runner-oidc@' created
# Idempotent: safe to re-run

set -euxo pipefail

GCP_PROJECT=${GCP_PROJECT:-nexusshield-prod}
SA_EMAIL=${SA_EMAIL:-runner-oidc@${GCP_PROJECT}.iam.gserviceaccount.com}
WIF_PROVIDER=${WIF_PROVIDER:-projects/151423364222/locations/global/workloadIdentityPools/runner-pool-20260311/providers/runner-provider-20260311}

echo "Configuring runner for Workload Identity federation"

# Create local config dir
mkdir -p /etc/nexusshield/runner
CONFIG_FILE=/etc/nexusshield/runner/oidc-config.env

cat > "$CONFIG_FILE" <<EOF
# Runner OIDC configuration (auto-generated)
GCP_PROJECT=${GCP_PROJECT}
WORKLOAD_IDENTITY_PROVIDER=${WIF_PROVIDER}
SERVICE_ACCOUNT=${SA_EMAIL}
# No service account keys; runner will exchange OIDC token against WIF
EOF

chmod 600 "$CONFIG_FILE" || true
chown root:root "$CONFIG_FILE" || true

cat <<EOF
Wrote runner OIDC configuration to: $CONFIG_FILE
To use on the runner, export the values and run the token exchange flow:

# Example manual token exchange (for testing):
# 1) obtain OIDC token from GitHub Actions or CI runner environment
#    (self-hosted runner must fetch an OIDC token using the platform mechanism)
# 2) exchange OIDC token for GCP access token using IAM STS

# Example (pseudo-steps):
# OIDC_TOKEN=<your_oidc_token>
# gcloud iam workload-identity-pools providers get-credentials --project=$GCP_PROJECT --workload-identity-provider="$WIF_PROVIDER" --service-account="$SA_EMAIL" --credential-file-override=/tmp/creds.json

# The recommended runner flow is to call the cloud provider's STS endpoint to exchange the OIDC assertion for a short-lived access token scoped to $SA_EMAIL.
EOF

exit 0
