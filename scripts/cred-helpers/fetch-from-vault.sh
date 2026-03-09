#!/usr/bin/env bash
set -euo pipefail

# Wrapper: fetch-from-vault
# Delegates to the unified credential manager with 'vault' retrieval.
if [ "$#" -lt 1 ]; then
  echo "Usage: $0 CREDENTIAL_NAME" >&2
  exit 2
fi
exec "$(dirname "$0")/../credential-manager.sh" "$1" vault
#!/usr/bin/env bash
set -euo pipefail
# Minimal Vault fetcher helper (placeholder for real implementation)
# Usage: fetch-from-vault.sh <credential-name>
NAME="$1"
VAR_NAME="TEST_VAULT_${NAME//[^A-Za-z0-9_]/_}"
if [ -n "${!VAR_NAME-}" ]; then
  echo "${!VAR_NAME}"
  exit 0
fi
if [ -n "${VAULT_ADDR-}" ] && [ -n "${VAULT_TOKEN-}" ]; then
  # attempt to read from KV v2 at secret/data/<NAME>
  resp=$(curl -sSf --header "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR/v1/secret/data/$NAME" 2>/dev/null || true)
  if [ -n "$resp" ]; then
    # try to extract data.data.value or data.data
    val=$(echo "$resp" | sed -n 's/.*"data".*"data".*"\([^"]*\)".*/\1/p' || true)
    # best-effort using jq if present
    if command -v jq >/dev/null 2>&1; then
      val=$(echo "$resp" | jq -r '.data.data | if type=="string" then . else .value // .secret // .password // .token end' 2>/dev/null || true)
    fi
    if [ -n "$val" ] && [ "$val" != "null" ]; then
      echo "$val"
      exit 0
    fi
  fi
fi
echo "ERROR: fetch-from-vault: secret $NAME not found (set env $VAR_NAME for testing or configure VAULT_ADDR/VAULT_TOKEN)" >&2
exit 2
