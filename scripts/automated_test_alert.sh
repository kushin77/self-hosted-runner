#!/bin/bash
# automated_test_alert.sh
# Sends a test alert to Alertmanager/Slack to verify the monitoring pipeline.

# Alertmanager URL (on node .42)
AM_URL="http://192.168.168.42:9093"

echo "Pushing synthetic alert to Alertmanager at ${AM_URL}..."

curl -H "Content-Type: application/json" -d '[
  {
    "labels": {
      "alertname": "TestManualAlert",
      "instance": "manual-test",
      "severity": "critical",
      "service": "runner-health"
    },
    "annotations": {
      "summary": "Manual Test Alert for Slack Integration",
      "description": "This is a synthetic alert to verify the Slack webhook is working correctly from Alertmanager on 192.168.168.42."
    }
  }
]' "${AM_URL}/api/v1/alerts"

echo -e "\n\nAlert pushed. Please check the Slack channel associated with your webhook."
