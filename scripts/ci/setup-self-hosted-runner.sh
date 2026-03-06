#!/usr/bin/env bash
set -euo pipefail

# Install and register GitHub Actions self-hosted runner
# Usage: setup-self-hosted-runner.sh <repo-url> <runner-name> <registration-token|-> [workdir] [vault-secret-path]
#
# If the third argument is '-' the script will try to retrieve the registration token
# from Vault (recommended). Provide the Vault secret path via the env var
# `VAULT_SECRET_PATH` or as the optional fifth argument when using '-' for the token.
# Environment variables required for Vault retrieval (if used):
# - VAULT_ADDR (e.g. https://vault.example.com)
# - VAULT_TOKEN (a token with permission to read the secret)
# The secret is expected to be a KV v2 secret with the token stored under key `token`.
# Example using Vault env:
# VAULT_ADDR=https://vault.example.com VAULT_TOKEN=s.xxxxx VAULT_SECRET_PATH=secret/data/ci/self-hosted/my-runner \
#   ./setup-self-hosted-runner.sh https://github.com/kushin77/self-hosted-runner my-runner - /opt/actions-runner

REPO_URL=${1:?repo url e.g. https://github.com/owner/repo}
RUNNER_NAME=${2:?runner name}
TOKEN_PARAM=${3:?registration token or '-'}
WORKDIR=${4:-/opt/actions-runner}

# Optional: VAULT_SECRET_PATH can be provided via env or as the 5th argument
VAULT_SECRET_PATH=${VAULT_SECRET_PATH:-${5:-}}

# Optional: pin runner version (e.g. 2.307.0). If set, the archive URL will use
# that explicit version. Use the env var `RUNNER_VERSION` to pin.
RUNNER_VERSION=${RUNNER_VERSION:-}

# If token param is '-', retrieve from Vault
if [ "$TOKEN_PARAM" = "-" ]; then
	if [ -z "$VAULT_SECRET_PATH" ]; then
		echo "When using '-' for the token parameter, VAULT_SECRET_PATH must be set (env) or passed as the 5th argument" >&2
		exit 1
	fi

	# Prefer Vault CLI when available; otherwise use HTTP API with retries and robust parsing
	if command -v vault >/dev/null 2>&1; then
		echo "Retrieving registration token from Vault (cli) at path: $VAULT_SECRET_PATH"
		TOKEN=$(vault kv get -field=token "$VAULT_SECRET_PATH" 2>/dev/null || true)
	else
		echo "Vault CLI not found; trying HTTP API using VAULT_ADDR and VAULT_TOKEN"
		if [ -z "$VAULT_ADDR" ] || [ -z "$VAULT_TOKEN" ]; then
			echo "VAULT_ADDR and VAULT_TOKEN must be set for HTTP retrieval" >&2
			exit 1
		fi

		JSON=""
		for i in 1 2 3; do
			JSON=$(curl -sSf --header "X-Vault-Token: $VAULT_TOKEN" --max-time 10 "$VAULT_ADDR/v1/$VAULT_SECRET_PATH" 2>/dev/null || true)
			if [ -n "$JSON" ]; then break; fi
			sleep $((i * 2))
		done

		if [ -z "$JSON" ]; then
			echo "Empty response from Vault after retries" >&2
			exit 1
		fi

		if command -v jq >/dev/null 2>&1; then
			TOKEN=$(echo "$JSON" | jq -r '.data.data.token // .data.token // .token // empty')
		else
			TOKEN=$(echo "$JSON" | python3 - <<'PY'
import sys,json
try:
	d=json.load(sys.stdin)
except Exception:
	print("")
	sys.exit(0)
for key in (('data', 'data', 'token'), ('data','token'), ('token',)):
	cur=d
	ok=True
	for k in key:
		if isinstance(cur,dict) and k in cur:
			cur=cur[k]
		else:
			ok=False
			break
	if ok and cur:
		print(cur)
		sys.exit(0)
print("")
PY
)
		fi
	fi

	if [ -z "$TOKEN" ]; then
		echo "Failed to retrieve token from Vault at $VAULT_SECRET_PATH" >&2
		exit 1
	fi
else
	TOKEN=$TOKEN_PARAM
fi

if [ -n "$RUNNER_VERSION" ]; then
	ARCHIVE_URL="https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64.tar.gz"
else
	ARCHIVE_URL="https://github.com/actions/runner/releases/latest/download/actions-runner-linux-x64.tar.gz"
fi

mkdir -p "$WORKDIR"
cd "$WORKDIR"

download_with_retries() {
	local url="$1" dest="$2" i
	for i in 1 2 3; do
		if curl -sSL --retry 3 --retry-delay 2 "$url" -o "$dest"; then
			return 0
		fi
		sleep $((i * 2))
	done
	return 1
}

echo "Downloading runner to $WORKDIR"
if ! download_with_retries "$ARCHIVE_URL" actions-runner.tar.gz; then
	echo "Failed to download runner archive from $ARCHIVE_URL" >&2
	exit 1
fi

echo "Extracting..."
tar xzf actions-runner.tar.gz
rm -f actions-runner.tar.gz

echo "Configuring runner ($RUNNER_NAME) for $REPO_URL"
./config.sh --unattended --url "$REPO_URL" --token "$TOKEN" --name "$RUNNER_NAME"

echo "Installing service"
sudo ./svc.sh install
sudo ./svc.sh start

echo "Self-hosted runner installed and started (name: $RUNNER_NAME)"

echo "To remove the runner: sudo ./svc.sh stop && sudo ./svc.sh uninstall && ./config.sh remove --token <token>"
