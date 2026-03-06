#!/bin/bash
# ==============================================================================
# SCRIPT: hands_off_yubikey_bootstrap.sh
# STRATEGY: Sovereign PGP/YubiKey Root-of-Trust (No-Cloud-Root)
# ==============================================================================
set -euo pipefail

# 1. Define the GPG ID for the YubiKey Owner
GPG_RECIPIENT_ID="${GPG_ID:-ops-yubikey@enterprise.com}"
ENCRYPTED_SEED_PATH="artifacts/vault/seed_from_yubikey.age"

echo "==== YUBIKEY/SOVEREIGN BOOTSTRAP INITIATED ===="

if [[ ! -f "$ENCRYPTED_SEED_PATH" ]]; then
    echo "ERROR: Encrypted seed [ $ENCRYPTED_SEED_PATH ] not found."
    echo "INSTRUCTION: Ops must run: 'gpg -e -r $GPG_RECIPIENT_ID seed.txt > $ENCRYPTED_SEED_PATH'"
    exit 1
fi

# 2. Decrypt via YubiKey (Interactively on the local terminal)
echo "ACTION: Decrypting ephemeral seed using Hardware Security Module (YubiKey)..."
# We pipe to age-keygen to transform the hardware-decrypted seed into an ephemeral age key
EPHEMERAL_KEY=$(gpg --decrypt "$ENCRYPTED_SEED_PATH")

# 3. Feed the decrypted seed into the DR Orchestrator
echo "SUCCESS: Seed decrypted from Hardware Token."
./scripts/ci/hands_off_dr_orchestration.sh --seed "$EPHEMERAL_KEY" --mode "sovereign"

echo "==== SOVEREIGN SESSION COMPLETE (EPHEMERAL) ===="
