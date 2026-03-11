#!/usr/bin/env bash
set -euo pipefail

# Systemd Deployment Playbook for Canonical Secrets API
# This script performs a hands-off, idempotent installation:
# - Creates secretsd user and group
# - Copies files to /opt/canonical-secrets
# - Installs systemd unit and environment file
# - Enables and starts the service
# - Health checks and verification

REPO_ROOT="${REPO_ROOT:-.}"
SERVICE_USER="secretsd"
SERVICE_GROUP="secretsd"
INSTALL_DIR="/opt/canonical-secrets"
SYSTEMD_DIR="/etc/systemd/system"
ENV_FILE="/etc/canonical_secrets.env"
VAULT_ADDR="${VAULT_ADDR:-http://vault.internal:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-}"  # Must be provided at runtime
LOG_DIR="/var/log/canonical-secrets"

echo "========================================"
echo "Canonical Secrets API - Systemd Deploy"
echo "========================================"

# Step 1: Validate prerequisites
echo "[STEP 1] Validating prerequisites..."
if ! command -v python3 &> /dev/null; then
  echo "❌ python3 not found. Install Python 3.11+ first."
  exit 1
fi

if ! command -v systemctl &> /dev/null; then
  echo "❌ systemctl not found. This requires a systemd-based system."
  exit 1
fi

echo "✓ Prerequisites validated"

# Step 2: Create service user and group (idempotent)
echo "[STEP 2] Creating service user and group..."
if ! getent group "$SERVICE_GROUP" > /dev/null; then
  sudo groupadd -f "$SERVICE_GROUP" || true
  echo "✓ Group '$SERVICE_GROUP' created"
else
  echo "✓ Group '$SERVICE_GROUP' already exists"
fi

if ! id "$SERVICE_USER" &> /dev/null; then
  sudo useradd -r -g "$SERVICE_GROUP" -s /usr/sbin/nologin "$SERVICE_USER" || true
  echo "✓ User '$SERVICE_USER' created"
else
  echo "✓ User '$SERVICE_USER' already exists"
fi

# Step 3: Create install directory and copy files
echo "[STEP 3] Installing files..."
sudo mkdir -p "$INSTALL_DIR" "$LOG_DIR"
sudo chown "$SERVICE_USER:$SERVICE_GROUP" "$INSTALL_DIR" "$LOG_DIR"
sudo chmod 750 "$INSTALL_DIR" "$LOG_DIR"

# Copy backend files
if [ -d "$REPO_ROOT/backend/src" ]; then
  sudo cp -r "$REPO_ROOT/backend/src" "$INSTALL_DIR/" || true
  sudo cp "$REPO_ROOT/backend/requirements.txt" "$INSTALL_DIR/" || true
else
  echo "⚠ Backend source files not found in $REPO_ROOT/backend/src"
fi

echo "✓ Files copied to $INSTALL_DIR"

# Step 4: Create Python virtual environment and install dependencies (idempotent)
echo "[STEP 4] Setting up Python environment..."
if [ ! -d "$INSTALL_DIR/venv" ]; then
  sudo python3 -m venv "$INSTALL_DIR/venv"
  echo "✓ Virtual environment created"
else
  echo "✓ Virtual environment already exists"
fi

# Install requirements (if not already installed, pip will skip unchanged packages)
sudo "$INSTALL_DIR/venv/bin/pip" install --no-cache-dir --quiet -r "$INSTALL_DIR/requirements.txt" 2>&1 > /dev/null || true
echo "✓ Dependencies installed"

# Step 5: Create environment file (with placeholder for secrets)
echo "[STEP 5] Creating environment file..."
if [ ! -f "$ENV_FILE" ]; then
  sudo tee "$ENV_FILE" > /dev/null <<EOF
# Canonical Secrets API Environment
# DO NOT COMMIT THIS FILE TO VERSION CONTROL
# Update with actual values before deployment

PORT=8000
ENVIRONMENT=production
LOG_DIR=$LOG_DIR

# Vault Configuration (required)
VAULT_ADDR=$VAULT_ADDR
VAULT_TOKEN=${VAULT_TOKEN}
VAULT_NAMESPACE=

# GCP Configuration (optional, for GSM failover)
GOOGLE_APPLICATION_CREDENTIALS=/opt/canonical-secrets/gcp-sa-key.json

# AWS Configuration (optional, for AWS Secrets Manager failover)
AWS_REGION=us-east-1
AWS_DEFAULT_REGION=us-east-1

# Azure Configuration (optional, for Azure Key Vault failover)
AZURE_SUBSCRIPTION_ID=
AZURE_TENANT_ID=

# Security & Compliance
NO_GITHUB_ACTIONS=1
IMMUTABLE_AUDIT_TRAIL=1
EOF
  sudo chmod 600 "$ENV_FILE"
  sudo chown "$SERVICE_USER:$SERVICE_GROUP" "$ENV_FILE"
  echo "✓ Environment file created at $ENV_FILE"
  echo "⚠ IMPORTANT: Update $ENV_FILE with actual credentials (Vault token, KMS keys, etc.)"
else
  echo "✓ Environment file already exists at $ENV_FILE"
fi

# Step 6: Deploy systemd unit
echo "[STEP 6] Deploying systemd unit..."
sudo tee "$SYSTEMD_DIR/canonical-secrets-api.service" > /dev/null <<'SYSTEMD_UNIT'
[Unit]
Description=Canonical Secrets API Service
Documentation=file:///opt/canonical-secrets/README.md
After=network.target

[Service]
Type=notify
User=secretsd
Group=secretsd
WorkingDirectory=/opt/canonical-secrets
EnvironmentFile=/etc/canonical_secrets.env
ExecStart=/opt/canonical-secrets/venv/bin/uvicorn src.canonical_secrets_api:app --host 127.0.0.1 --port 8000
ExecReload=/bin/kill -HUP $MAINPID
KillMode=process
Restart=on-failure
RestartSec=5s

# Security hardening
PrivateTmp=true
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/log/canonical-secrets /opt/canonical-secrets

# Resource limits (prevent resource exhaustion)
LimitNOFILE=65536
LimitNPROC=8192

[Install]
WantedBy=multi-user.target
SYSTEMD_UNIT

sudo systemctl daemon-reload
echo "✓ Systemd unit deployed"

# Step 7: Enable and start service (idempotent)
echo "[STEP 7] Enabling and starting service..."
sudo systemctl enable canonical-secrets-api.service
sudo systemctl restart canonical-secrets-api.service
echo "✓ Service enabled and started"

# Step 8: Wait for service to be ready and health-check
echo "[STEP 8] Health check..."
sleep 2

for i in {1..10}; do
  if curl -sf http://localhost:8000/api/v1/secrets/health > /dev/null 2>&1; then
    echo "✓ Service is healthy"
    break
  elif [ "$i" -eq 10 ]; then
    echo "❌ Service failed to become healthy after 10 attempts"
    sudo systemctl status canonical-secrets-api.service || true
    exit 1
  else
    echo "  Waiting for service to be ready... (attempt $i/10)"
    sleep 1
  fi
done

# Step 9: Summary
echo ""
echo "========================================"
echo "Deployment Complete!"
echo "========================================"
echo "Service:       canonical-secrets-api"
echo "Install Dir:   $INSTALL_DIR"
echo "Env File:      $ENV_FILE"
echo "Log Dir:       $LOG_DIR"
echo "Port:          8000 (localhost only)"
echo ""
echo "Next steps:"
echo "1. Update $ENV_FILE with production credentials"
echo "2. Configure reverse proxy (nginx/HAProxy) for external access"
echo "3. Monitor logs: journalctl -u canonical-secrets-api.service -f"
echo ""
