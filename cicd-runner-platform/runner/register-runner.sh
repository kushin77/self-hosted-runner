#!/usr/bin/env bash
##
## Register GitHub Actions Runner
## Registers a runner with GitHub or GitHub Enterprise.
##
set -euo pipefail

RUNNER_HOME="${RUNNER_HOME:-/opt/actions-runner}"
RUNNER_USER="${RUNNER_USER:-runner}"

# Parse arguments
RUNNER_URL=""
TOKEN=""
LABELS=""
GROUP=""
WORK=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --url)
      RUNNER_URL="$2"
      shift 2
      ;;
    --token)
      TOKEN="$2"
      shift 2
      ;;
    --labels)
      LABELS="$2"
      shift 2
      ;;
    --group)
      GROUP="$2"
      shift 2
      ;;
    --work)
      WORK="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

if [ -z "${RUNNER_URL}" ] || [ -z "${TOKEN}" ]; then
  echo "Usage: $0 --url <url> --token <token> [--labels <labels>] [--group <group>] [--work <work>]"
  exit 1
fi

echo "Registering runner..."
echo "  URL: ${RUNNER_URL}"
echo "  Labels: ${LABELS}"

# Build config command
CONFIG_CMD="cd ${RUNNER_HOME} && sudo -u ${RUNNER_USER} ./config.sh --unattended"
CONFIG_CMD="${CONFIG_CMD} --url '${RUNNER_URL}'"
CONFIG_CMD="${CONFIG_CMD} --token '${TOKEN}'"
CONFIG_CMD="${CONFIG_CMD} --runnergroup '${GROUP:-Default}'"

if [ -n "${LABELS}" ]; then
  CONFIG_CMD="${CONFIG_CMD} --labels '${LABELS}'"
fi

if [ -n "${WORK}" ]; then
  CONFIG_CMD="${CONFIG_CMD} --work '${WORK}'"
fi

# Add runner identity metadata
CONFIG_CMD="${CONFIG_CMD} --name '$(hostname)'"

# Execute registration
eval "${CONFIG_CMD}"

echo "✓ Runner registered successfully"
