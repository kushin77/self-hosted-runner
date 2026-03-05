#!/bin/bash
INTERVAL=${1:-120}
ENDPOINT="192.168.168.42:6443"
REPO="kushin77/self-hosted-runner"
ISSUE_NUM=343

echo "Starting Staging Cluster Monitor for $ENDPOINT (Interval: ${INTERVAL}s)..."

while true; do
    if nc -zv 192.168.168.42 6443 2>&1 | grep -q succeeded; then
        TIMESTAMP=$(date)
        gh issue comment $ISSUE_NUM --body "✅ SUCCESS: Staging Cluster API ($ENDPOINT) is now reachable as of $TIMESTAMP. Resuming Phase P4 validation."
        echo "Cluster reachable. Notification sent to issue #$ISSUE_NUM."
        # If reachable, we can stop the monitor or keep it running to detect flaps. 
        # For now, we exit to avoid spam.
        exit 0
    fi
    sleep $INTERVAL
done
