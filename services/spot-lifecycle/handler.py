#!/usr/bin/env python3
"""
Simple AWS Lambda/SQS handler prototype that processes AutoScaling lifecycle
notifications and triggers a graceful runner drain via a configurable webhook.

This is a prototype — in production, run with robust retries, observability,
and secure credentials (IAM role, secrets manager for webhooks, etc.).
"""
import os
import json
import logging
import urllib.request
import boto3
from botocore.exceptions import BotoCoreError, ClientError

LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO")
DRIVER_WEBHOOK = os.getenv("RUNNER_DRAIN_WEBHOOK", "")
RUNNER_DRAIN_SECRET_ARN = os.getenv("RUNNER_DRAIN_SECRET_ARN", "")

# Lazy Secrets Manager client
_secrets_client = None


def _get_secret_value(secret_arn: str) -> str | None:
    global _secrets_client
    if not secret_arn:
        return None
    if _secrets_client is None:
        _secrets_client = boto3.client("secretsmanager")
    try:
        resp = _secrets_client.get_secret_value(SecretId=secret_arn)
        return resp.get("SecretString")
    except (BotoCoreError, ClientError) as e:
        logger.exception("Failed to read secret %s: %s", secret_arn, e)
        return None

logging.basicConfig(level=LOG_LEVEL)
logger = logging.getLogger("spot-lifecycle")


def call_drain_webhook(instance_id: str, asg_name: str) -> None:
    webhook = DRIVER_WEBHOOK
    # If a secret ARN is provided, attempt to read the webhook URL from Secrets Manager
    if RUNNER_DRAIN_SECRET_ARN and not webhook:
        secret_val = _get_secret_value(RUNNER_DRAIN_SECRET_ARN)
        if secret_val:
            webhook = secret_val.strip()

    if not webhook:
        logger.warning("No RUNNER_DRAIN_WEBHOOK configured and no secret found; skipping drain call")
        return

    payload = json.dumps({"instance_id": instance_id, "asg": asg_name}).encode("utf-8")
    req = urllib.request.Request(webhook, data=payload, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            logger.info("Webhook responded: %s", resp.status)
    except Exception as e:
        logger.exception("Failed to call drain webhook: %s", e)


def parse_message(msg_body: str):
    # ASG lifecycle notifications are generally in JSON; attempt to parse common fields
    try:
        obj = json.loads(msg_body)
    except Exception:
        logger.debug("Message not JSON; passing through")
        return None

    # Example field names: EC2InstanceId, AutoScalingGroupName
    instance_id = obj.get("EC2InstanceId") or obj.get("instance_id")
    asg = obj.get("AutoScalingGroupName") or obj.get("auto_scaling_group_name")
    return {"instance_id": instance_id, "asg": asg}


def lambda_handler(event, context):
    logger.info("Received event: %s", event.keys())
    for record in event.get("Records", []):
        body = record.get("body") or record.get("Sns", {}).get("Message")
        if not body:
            logger.debug("No body found on record")
            continue

        parsed = parse_message(body)
        if not parsed:
            logger.debug("Could not parse message body; skipping")
            continue

        instance_id = parsed.get("instance_id")
        asg = parsed.get("asg")
        logger.info("Processing lifecycle for instance=%s asg=%s", instance_id, asg)

        # Call the configured drain webhook which should implement graceful drain
        call_drain_webhook(instance_id, asg)

    return {"status": "ok"}


if __name__ == "__main__":
    # Local test runner
    sample = {"EC2InstanceId": "i-0123456789abcdef0", "AutoScalingGroupName": "runner-asg"}
    lambda_handler({"Records": [{"body": json.dumps(sample)}]}, None)
