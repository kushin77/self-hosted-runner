#!/usr/bin/env bash
set -eu

# provision-secrets.sh
# Template to provision secrets into target secret manager (Vault / GSM /KMS).
# This script is intentionally a no-op placeholder that documents recommended
# patterns and provides CLI examples. Do NOT hardcode secrets here.

usage(){
  cat <<EOF
Usage: $0 [vault|gsm|gcp-kms] --name <secret_name> --value-from <file|env|stdin>

Examples:
  # Vault (kv v2)
  ./provision-secrets.sh vault --name nexusshield/postgres --value-from file:./secrets/postgres.json

  # Google Secret Manager (gcloud)
  ./provision-secrets.sh gsm --name projects/PROJECT/secrets/nexusshield-postgres --value-from file:./secrets/postgres.json

  # AWS KMS: store encrypted blob in secure storage and record ARN in Vault
  ./provision-secrets.sh gcp-kms --name projects/PROJECT/locations/global/keyRings/kr/cryptoKeys/key --value-from env:POSTGRES_SECRET
EOF
}

if [ "$#" -lt 1 ]; then
  usage
  exit 1
fi

PROVIDER="$1"; shift
NAME=""; VALUE_SRC=""
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --name) NAME="$2"; shift 2;;
    --value-from) VALUE_SRC="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg $1"; usage; exit 2;;
  esac
done

if [ -z "$NAME" ] || [ -z "$VALUE_SRC" ]; then
  usage; exit 2
fi

echo "Provisioning secret '$NAME' via provider '$PROVIDER' (value source: $VALUE_SRC)"

case "$PROVIDER" in
  vault)
    # Example: vault kv put secret/nexusshield/postgres @secrets/postgres.json
    echo "Run: vault kv put $NAME <file>" ;;
  gsm)
    # Example: gcloud secrets create ... then gcloud secrets versions add ...
    echo "Run: gcloud secrets versions add $NAME --data-file=<file>" ;;
  gcp-kms)
    echo "Use KMS to encrypt data and store ciphertext in secure storage; record key ARN in Vault/GSM." ;;
  *) echo "Unsupported provider: $PROVIDER"; exit 3;;
esac

echo "Done (this is a template — follow the commented examples for your environment)."
#!/usr/bin/env bash
set -euo pipefail
# Provision secrets into target host using Vault/GSM/KMS patterns.
# This script is a template. Integrate with your secret backend and auth.

TARGET=${1:-}
if [ -z "$TARGET" ]; then
  echo "Usage: $0 user@host" >&2
  exit 2
fi

echo "This script will:"
echo " - Fetch secrets from Vault/GSM/KMS (operator must have access)"
echo " - Write a .env file on the target host under the deployment directory"

# TODO: Replace the following placeholder commands with your commands.
# Example (Vault):
# tkn=$(vault login -method=aws -field=token)
# postgres_pw=$(vault kv get -field=password secret/nexusshield/database)

POSTGRES_PW_PLACEHOLDER="REPLACE_ME_POSTGRES_PW"
REDIS_PW_PLACEHOLDER="REPLACE_ME_REDIS_PW"
GRAFANA_PW_PLACEHOLDER="REPLACE_ME_GRAFANA_PW"

cat > /tmp/.env.deploy <<EOF
POSTGRES_PW=${POSTGRES_PW_PLACEHOLDER}
REDIS_PW=${REDIS_PW_PLACEHOLDER}
GRAFANA_PW=${GRAFANA_PW_PLACEHOLDER}
EOF

echo "Uploading .env to ${TARGET}:~/deployments/current/.env"
scp /tmp/.env.deploy "${TARGET}:~/deployments/current/.env"
rm -f /tmp/.env.deploy

echo "Secrets provisioned (placeholder). Replace with real integration."
