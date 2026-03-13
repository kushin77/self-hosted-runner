#!/usr/bin/env bash
set -euo pipefail

# Provision ALERT_WEBHOOK for smoke-check on a remote worker
# Usage: ./provision-alert-webhook.sh user@worker [secret-name...]

REMOTE=${1:-}
shift || true
if [[ -z "$REMOTE" ]]; then
  echo "Usage: $0 user@worker [secret-name...]" >&2
  exit 1
fi

SECRETS=("portal/ALERT_WEBHOOK" "ALERT_WEBHOOK" "portal/alert_webhook" "$@")

echo "Provisioning ALERT_WEBHOOK on $REMOTE (probing: ${SECRETS[*]})"

ssh "$REMOTE" bash -s <<'SSH'
set -euo pipefail
WORKDIR=~/self-hosted-runner/portal/docker
cd "$WORKDIR"

# function to try gcloud
try_gcloud() {
  secret_name="$1"
  if command -v gcloud >/dev/null 2>&1; then
    if gcloud secrets versions access latest --secret="$secret_name" >/dev/null 2>&1; then
      gcloud secrets versions access latest --secret="$secret_name"
      return 0
    fi
  fi
  return 1
}

# function to try vault
try_vault() {
  secret_name="$1"
  if command -v vault >/dev/null 2>&1; then
    # try common kv path
    if vault kv get -field=value secret/portal/${secret_name} >/dev/null 2>&1; then
      vault kv get -field=value secret/portal/${secret_name}
      return 0
    fi
    if vault kv get -field=value secret/${secret_name} >/dev/null 2>&1; then
      vault kv get -field=value secret/${secret_name}
      return 0
    fi
  fi
  return 1
}

WEBHOOK=
for s in "${SECRETS[@]}"; do
  if value=$(try_gcloud "$s" 2>/dev/null || true); then
    WEBHOOK="$value"
    break
  fi
  if value=$(try_vault "$s" 2>/dev/null || true); then
    WEBHOOK="$value"
    break
  fi
done

if [[ -z "${WEBHOOK:-}" ]]; then
  echo "No webhook secret found on worker via gcloud/vault. Provide secret or set manually." >&2
  exit 2
fi

echo "Webhook found; installing systemd drop-in"
DROP_DIR=/etc/systemd/system/smoke-check.service.d
sudo mkdir -p "$DROP_DIR"
sudo tee "$DROP_DIR/override.conf" > /dev/null <<EOF
[Service]
Environment="ALERT_WEBHOOK=${WEBHOOK}"
Environment="ALERT_THRESHOLD=2"
Environment="ALERT_COOLDOWN_SECONDS=1800"
EOF

sudo systemctl daemon-reload
sudo systemctl restart smoke-check.timer || sudo systemctl start smoke-check.timer

echo "Webhook installed and timer restarted. Running a test alert (will respect threshold logic)."
sudo -u "$USER" bash -c 'HOME=/home/$USER /home/$USER/self-hosted-runner/portal/docker/alert-on-failure.sh "Test alert from provision script"'

echo "Done."
SSH
