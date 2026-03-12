#!/usr/bin/env bash
set -euo pipefail

# infra/deploy-runner-oidc.sh
# Helper to generate Workload Identity credential config for a self-hosted runner
# and create a token-refresh helper that writes a short-lived access token to disk.
#
# Usage (dry-run first):
#   bash infra/deploy-runner-oidc.sh --dry-run \
#     --project=nexusshield-prod \
#     --pool=runner-pool-20260311 \
#     --provider=runner-provider-20260311 \
#     --service-account=runner-oidc@nexusshield-prod.iam.gserviceaccount.com

PROG="$(basename "$0")"
DRY_RUN=0
PROJECT=""
POOL=""
PROVIDER=""
SERVICE_ACCOUNT=""
OUT_DIR="infra/run-creds"

usage(){
  cat <<EOF
Usage: $PROG [--dry-run] --project=PROJECT --pool=POOL --provider=PROVIDER --service-account=SA

Generates a Workload Identity credential config (creds.json) usable by gcloud
and creates a local token refresh helper and systemd unit (placed in repo under infra/).

This script does NOT modify the host system by default. Use without --dry-run to
write credential config to 
  $OUT_DIR/creds.json
and token helper at
  $OUT_DIR/refresh-token.sh

Recommended flow (admin on runner host):
  1. Copy generated $OUT_DIR/creds.json to runner host (secure)
  2. Place refresh systemd unit on host and enable
  3. Configure runner to read /run/nexusshield/runner-access-token

EOF
}

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1; shift || true;;
    --project=*) PROJECT="${arg#*=}"; shift || true;;
    --pool=*) POOL="${arg#*=}"; shift || true;;
    --provider=*) PROVIDER="${arg#*=}"; shift || true;;
    --service-account=*) SERVICE_ACCOUNT="${arg#*=}"; shift || true;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $arg"; usage; exit 1;;
  esac
done

if [ -z "$PROJECT" ] || [ -z "$POOL" ] || [ -z "$PROVIDER" ] || [ -z "$SERVICE_ACCOUNT" ]; then
  echo "Missing required parameters." >&2
  usage
  exit 2
fi

mkdir -p "$OUT_DIR"

CREDS_PATH="$OUT_DIR/creds.json"

echo "⟲ Generating Workload Identity credential config (creds.json)"
CMD=(gcloud iam workload-identity-pools create-cred-config \
  projects/${PROJECT}/locations/global/workloadIdentityPools/${POOL}/providers/${PROVIDER} \
  --service-account=${SERVICE_ACCOUNT} \
  --output-file="$CREDS_PATH")

if [ "$DRY_RUN" -eq 1 ]; then
  echo "DRY RUN: ${CMD[*]}"
else
  echo "Running: ${CMD[*]}"
  "${CMD[@]}"
  echo "✅ Wrote credential config: $CREDS_PATH"
fi

# Token refresh helper
REFRESH_SH="$OUT_DIR/refresh-token.sh"
cat > "$REFRESH_SH" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
# refresh-token.sh - obtain short-lived access token using creds.json
CREDS="$(dirname "$0")/creds.json"
OUT_DIR="/run/nexusshield"
OUT_FILE="$OUT_DIR/runner-access-token"
mkdir -p "$OUT_DIR"
if [ ! -f "$CREDS" ]; then
  echo "creds.json not found at $CREDS" >&2
  exit 2
fi
# Use gcloud to print an access token using the credential config
TOKEN=$(gcloud auth application-default print-access-token --credential-file-override="$CREDS")
if [ -z "$TOKEN" ]; then
  echo "Failed to obtain access token" >&2
  exit 3
fi
echo "$TOKEN" > "$OUT_FILE"
chmod 640 "$OUT_FILE"
echo "Wrote token to $OUT_FILE"
BASH

chmod +x "$REFRESH_SH"

SYSTEMD_SERVICE_FILE="infra/runner-token-refresh.service"
cat > "$SYSTEMD_SERVICE_FILE" <<'UNIT'
[Unit]
Description=Refresh NexusShield runner access token
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash /home/akushnir/self-hosted-runner/infra/run-creds/refresh-token.sh
User=root
Group=root

[Install]
WantedBy=multi-user.target
UNIT

SYSTEMD_TIMER_FILE="infra/runner-token-refresh.timer"
cat > "$SYSTEMD_TIMER_FILE" <<'TIMER'
[Unit]
Description=Run runner token refresh every 45 minutes

[Timer]
OnBootSec=1min
OnUnitActiveSec=45min

[Install]
WantedBy=timers.target
TIMER

echo "Created: $REFRESH_SH, $SYSTEMD_SERVICE_FILE, $SYSTEMD_TIMER_FILE"

if [ "$DRY_RUN" -eq 1 ]; then
  echo "DRY RUN complete. To deploy on runner host:"
  echo "  scp -r $OUT_DIR runner-host:/etc/nexusshield/"
  echo "  sudo cp infra/runner-token-refresh.{service,timer} /etc/systemd/system/ && sudo systemctl daemon-reload && sudo systemctl enable --now runner-token-refresh.timer"
  exit 0
fi

echo "Deployment artifacts written to $OUT_DIR (commit these files to repo and securely transfer creds.json to runner host)."

exit 0
