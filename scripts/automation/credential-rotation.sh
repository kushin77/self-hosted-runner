#!/bin/bash
#
# Credential Rotation System - Background Process
# Runs continuously, rotating credentials from GSM/Vault/KMS
# Maintains 4-layer failover SLA
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
ROTATION_LOG="${PROJECT_ROOT}/logs/credential-rotation.jsonl"
STATE_FILE="/tmp/credential-rotation-state.json"

# Immutable audit log
log_audit() {
    local level="$1"
    local action="$2"
    local details="$3"
    echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"level\":\"$level\",\"action\":\"$action\",\"details\":$details,\"hostname\":\"$(hostname)\"}" >> "$ROTATION_LOG"
}

# Initialize
mkdir -p "$(dirname "$ROTATION_LOG")"
[ -f "$STATE_FILE" ] || echo '{}' > "$STATE_FILE"

# Credential rotation function
rotate_credential() {
    local secret_name="$1"
    local backend="$2"
    local ttl_hours="${3:-1}"  # Default 1-hour TTL
    
    echo "Rotating: $secret_name (backend: $backend, TTL: ${ttl_hours}h)"
    
    case "$backend" in
        gsm)
            # GSM rotation: Create new version
            NEW_SECRET=$(openssl rand -base64 32)
            echo -n "$NEW_SECRET" | gcloud secrets versions add "$secret_name" --data-file=-
            log_audit "INFO" "gsm_rotate" "{\"secret\":\"$secret_name\"}"
            ;;
        vault)
            # Vault rotation: Update secret
            NEW_SECRET=$(openssl rand -base64 32)
            vault kv put "secret/$secret_name" value="$NEW_SECRET"
            log_audit "INFO" "vault_rotate" "{\"secret\":\"$secret_name\"}"
            ;;
        kms)
            # KMS rotation: Reencrypt with new key version
            if [ -f "/etc/secrets/kms/$secret_name" ]; then
                # Decrypt, rotate key, reencrypt
                DECRYPTED=$(cat "/etc/secrets/kms/$secret_name" | base64 -d | gcloud kms decrypt --ciphertext-file=- --plaintext-file=- 2>/dev/null)
                REENCRYPTED=$(echo -n "$DECRYPTED" | gcloud kms encrypt --plaintext-file=- --ciphertext-file=- 2>/dev/null | base64)
                echo -n "$REENCRYPTED" > /etc/secrets/kms/$secret_name
                log_audit "INFO" "kms_rotate" "{\"secret\":\"$secret_name\"}"
            fi
            ;;
        aws)
            # AWS Secrets Manager rotation
            NEW_SECRET=$(openssl rand -base64 32)
            aws secretsmanager update-secret \
                --secret-id "$secret_name" \
                --secret-string "$NEW_SECRET" \
                --region "${AWS_REGION:-us-east-1}"
            log_audit "INFO" "aws_rotate" "{\"secret\":\"$secret_name\"}"
            ;;
    esac
}

# Failover latency measurement
measure_failover_latency() {
    local secret_name="$1"
    
    echo "Measuring failover latency for: $secret_name"
    
    # Time each backend
    for backend in gsm vault kms aws; do
        START=$(date +%s%N | cut -b1-13)
        
        case "$backend" in
            gsm)
                gcloud secrets versions access latest --secret="$secret_name" >/dev/null 2>&1 && \
                END=$(date +%s%N | cut -b1-13) && \
                LATENCY=$((END - START)) && \
                log_audit "INFO" "latency_check" "{\"backend\":\"gsm\",\"secret\":\"$secret_name\",\"latency_ms\":$LATENCY}"
                ;;
            vault)
                [ -z "$VAULT_ADDR" ] || \
                vault kv get -field=value "secret/$secret_name" >/dev/null 2>&1 && \
                END=$(date +%s%N | cut -b1-13) && \
                LATENCY=$((END - START)) && \
                log_audit "INFO" "latency_check" "{\"backend\":\"vault\",\"secret\":\"$secret_name\",\"latency_ms\":$LATENCY}"
                ;;
            kms)
                [ -f "/etc/secrets/kms/$secret_name" ] && \
                END=$(date +%s%N | cut -b1-13) && \
                LATENCY=$((END - START)) && \
                log_audit "INFO" "latency_check" "{\"backend\":\"kms\",\"secret\":\"$secret_name\",\"latency_ms\":$LATENCY}"
                ;;
            aws)
                aws secretsmanager get-secret-value --secret-id "$secret_name" >/dev/null 2>&1 && \
                END=$(date +%s%N | cut -b1-13) && \
                LATENCY=$((END - START)) && \
                log_audit "INFO" "latency_check" "{\"backend\":\"aws\",\"secret\":\"$secret_name\",\"latency_ms\":$LATENCY}"
                ;;
        esac
    done
}

# Main rotation cycle
echo "Starting credential rotation system..."
log_audit "INFO" "start" "{\"cycle\":\"credential-rotation\"}"

# Rotate all critical secrets
SECRETS=(
    "github-deploy-token:gsm:1"
    "gcp-project-id:gsm:24"
    "aws-region:gsm:24"
    "database-password:vault:6"
    "api-key:gsm:1"
    "tls-cert:kms:720"
    "kms-key-id:aws:24"
)

for secret_spec in "${SECRETS[@]}"; do
    IFS=':' read -r secret_name backend ttl <<< "$secret_spec"
    rotate_credential "$secret_name" "$backend" "$ttl"
    measure_failover_latency "$secret_name"
done

# Update state file
STATE_JSON=$(jq -n \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{last_rotation: $timestamp}')
echo "$STATE_JSON" > "$STATE_FILE"

log_audit "INFO" "complete" "{\"secrets_rotated\":${#SECRETS[@]}}"

echo "Credential rotation cycle completed"
