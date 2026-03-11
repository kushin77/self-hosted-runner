#!/usr/bin/env python3
"""
Create alert policy for synthetic health checks (idempotent).
Stores configuration in Cloud Monitoring using gcloud.
"""
import subprocess
import json
import sys

PROJECT_ID = "nexusshield-prod"
POLICY_NAME = "synthetic-uptime-check-failure-alert"
EMAIL_CHANNEL = "projects/nexusshield-prod/notificationChannels/16284129900945210911"
CRITICAL_CHANNEL = "projects/nexusshield-prod/notificationChannels/8473220498823178928"

def check_existing_policy():
    """Check if alert policy already exists."""
    try:
        result = subprocess.run(
            [
                "gcloud", "monitoring", "policies", "list",
                f"--project={PROJECT_ID}",
                f"--filter=displayName:{POLICY_NAME}",
                "--format=value(name)"
            ],
            capture_output=True,
            text=True,
            timeout=30
        )
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip().split('\n')[0]
    except subprocess.TimeoutExpired:
        print("Warning: timeout checking existing policies", file=sys.stderr)
    return None

def create_policy():
    """Create alert policy using gcloud."""
    policy_def = {
        "displayName": POLICY_NAME,
        "conditions": [
            {
                "displayName": "Synthetic log metric count < 1 in 5 minutes",
                "conditionThreshold": {
                    "filter": 'metric.type = "logging.googleapis.com/user/synthetic_uptime_log_count"',
                    "comparison": "COMPARISON_LT",
                    "thresholdValue": 1,
                    "duration": "300s",
                    "aggregations": [
                        {
                            "alignmentPeriod": "60s",
                            "perSeriesAligner": "ALIGN_SUM"
                        }
                    ]
                }
            }
        ],
        "combiner": "OR",
        "notificationChannels": [EMAIL_CHANNEL, CRITICAL_CHANNEL]
    }
    
    # Create via gcloud
    cmd = [
        "gcloud", "monitoring", "policies", "create",
        f"--project={PROJECT_ID}",
        "--update-channels"
    ]
    
    try:
        # Use stdin to pass the policy definition
        result = subprocess.run(
            cmd + [json.dumps(policy_def)],
            timeout=30,
            capture_output=True,
            text=True
        )
        if result.returncode == 0:
            print("Alert policy created/updated successfully", file=sys.stderr)
            return True
        else:
            print(f"Failed: {result.stderr}", file=sys.stderr)
            return False
    except subprocess.TimeoutExpired:
        print("Timeout creating policy", file=sys.stderr)
        return False

if __name__ == "__main__":
    existing = check_existing_policy()
    if existing:
        print(f"Alert policy already exists: {existing}", file=sys.stderr)
        sys.exit(0)
    
    if create_policy():
        sys.exit(0)
    else:
        sys.exit(1)
