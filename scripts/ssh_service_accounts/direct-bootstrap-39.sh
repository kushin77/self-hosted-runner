#!/bin/bash
# Direct bootstrap of elevatediq-svc-dev-nas@192.168.168.39
# Uses sshpass to set up SSH key auth on NAS

set -euo pipefail

readonly HOST="192.168.168.39"
readonly USER="kushin77"
readonly SVC_NAME="elevatediq-svc-dev-nas"
readonly PUBKEY_PATH="secrets/ssh/elevatediq-svc-dev-nas/id_ed25519.pub"
readonly WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_error() { echo -e "${RED}✗${NC} $1" >&2; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_info() { echo -e "${BLUE}▶${NC} $1"; }

# Verify public key exists
if [ ! -f "$PUBKEY_PATH" ]; then
    log_error "Public key not found: $PUBKEY_PATH"
    exit 1
fi

read -sp "Enter password for ${USER}@${HOST}: " PASSWORD
echo ""

PUBKEY=$(cat "$PUBKEY_PATH")

log_info "Bootstrapping $SVC_NAME on $HOST..."

# Step 1: Create service account
log_info "Creating service account..."
sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=accept-new \
    "${USER}@${HOST}" << 'EOF'
set -e
SVC_NAME="elevatediq-svc-dev-nas"
read -r PUBKEY

# Create user if missing
if ! sudo id "$SVC_NAME" &>/dev/null 2>&1; then
    sudo useradd -r -s /bin/bash -m -d "/home/$SVC_NAME" "$SVC_NAME"
fi

# Configure .ssh
SSH_DIR="/home/$SVC_NAME/.ssh"
sudo mkdir -p "$SSH_DIR"
sudo bash -c "cat >> '$SSH_DIR/authorized_keys' << 'PUBKEY'
$PUBKEY
PUBKEY"
sudo chown -R "$SVC_NAME:$SVC_NAME" "$SSH_DIR"
sudo chmod 700 "$SSH_DIR"
sudo chmod 600 "$SSH_DIR/authorized_keys"

echo "[✓] Service account $SVC_NAME is ready"
EOF <<< "$PUBKEY"

log_success "Service account created on $HOST"

# Step 2: Test SSH key auth
log_info "Testing SSH key auth..."
if timeout 5 ssh -o BatchMode=yes -i "$WORKSPACE_ROOT/$PUBKEY_PATH" \
    "${SVC_NAME}@${HOST}" "id" &>/dev/null; then
    log_success "SSH key auth working for $SVC_NAME@$HOST"
else
    log_error "SSH key auth failed for $SVC_NAME@$HOST"
    exit 1
fi

log_success "Bootstrap complete!"
