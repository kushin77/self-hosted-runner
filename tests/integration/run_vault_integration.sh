#!/usr/bin/env bash
set -euo pipefail
DIR=$(cd "$(dirname "$0")" && pwd)
cd "$DIR/vault"

echo "Starting Vault dev server..."
docker compose up -d

trap 'echo "Cleaning up..."; docker compose down' EXIT

export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=devroot

./setup_vault.sh

# Test get-runner-token.sh
TOKEN=$(../../../../scripts/ci/get-runner-token.sh secret/data/ci/self-hosted/test-runner --vault-addr $VAULT_ADDR)
if [ "$TOKEN" != "test-registration-token" ]; then
  echo "Token mismatch: got '$TOKEN'" >&2
  exit 1
fi

echo "get-runner-token.sh returned expected token"

# Test rotate-runner.sh in dry-run mode (won't modify anything)
# Create a temp runner dir with dummy config.sh and svc.sh
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' RETURN
mkdir -p "$TMPDIR"
cat > "$TMPDIR/config.sh" <<'SH'
#!/usr/bin/env bash
if [ "$1" = "--unattended" ]; then
  echo "config simulated"
else
  echo "config command: $@"
fi
SH
chmod +x "$TMPDIR/config.sh"
cat > "$TMPDIR/svc.sh" <<'SH'
#!/usr/bin/env bash
case "$1" in
  install) echo "svc install" ;; start) echo "svc start" ;; stop) echo "svc stop" ;; run) echo "svc run" ;; *) echo "svc $@" ;;
esac
SH
chmod +x "$TMPDIR/svc.sh"

# Run rotate in dry mode
DRY=1 VAULT_ADDR=$VAULT_ADDR VAULT_TOKEN=devroot ../../../../scripts/ci/rotate-runner.sh "$TMPDIR" "https://github.com/owner/repo" "test-runner" secret/data/ci/self-hosted/test-runner

echo "rotate-runner.sh dry-run completed"
