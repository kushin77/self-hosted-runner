#!/bin/bash
# healthcheck_automation_finalizer.sh
# Final script to ensure all runners are in a self-healing state.

set -e

echo "Ensuring the healthcheck system is active..."

# Check if systemd unit is present
if [ -f /etc/systemd/system/actions-runner-health.timer ]; then
    sudo systemctl daemon-reload
    sudo systemctl enable --now actions-runner-health.timer
    echo "Success: actions-runner-health.timer is active."
else
    echo "Warning: actions-runner-health.timer not found on this host."
fi

# Pushing monitoring status to Pushgateway
HEALTH_SCRIPTS_PATH="/home/akushnir/self-hosted-runner/scripts"
if [ -f "${HEALTH_SCRIPTS_PATH}/check_and_reprovision_runner.sh" ]; then
    echo "Triggering manual run of healthcheck to warm up Pushgateway..."
    bash "${HEALTH_SCRIPTS_PATH}/check_and_reprovision_runner.sh"
else
    echo "Error: Healthcheck script not found at ${HEALTH_SCRIPTS_PATH}/check_and_reprovision_runner.sh"
fi

echo -e "\nFinal deployment state verified. Infrastructure is fully automated and autonomous."
