import os
import time
import logging
import requests
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token
import google.auth
from google.cloud import monitoring_v3

logging.basicConfig(level=logging.INFO)

TARGET_URL = os.environ.get("TARGET_URL")
METRIC_TYPE = os.environ.get("METRIC_TYPE", "custom.googleapis.com/synthetic/uptime_check")

def fetch_id_token(audience: str) -> str:
    auth_req = google_requests.Request()
    token = id_token.fetch_id_token(auth_req, audience)
    return token

def write_metric(project_id: str, metric_type: str, value: int):
    client = monitoring_v3.MetricServiceClient()
    project_name = f"projects/{project_id}"
    now = time.time()
    end_seconds = int(now)
    end_nanos = int((now - end_seconds) * 10 ** 9)
    # For gauge metrics the start_time must equal end_time; set both equal
    start_seconds = end_seconds
    start_nanos = end_nanos
    point = {
        "interval": {
            "start_time": {"seconds": start_seconds, "nanos": start_nanos},
            "end_time": {"seconds": end_seconds, "nanos": end_nanos},
        },
        "value": {"int64_value": value},
    }
    series = {
        "metric": {"type": metric_type},
        "resource": {"type": "global"},
        "points": [point],
    }

    max_attempts = 3
    backoff = 1
    for attempt in range(1, max_attempts + 1):
        try:
            logging.info("Attempt %d: writing metric %s value=%s", attempt, metric_type, value)
            client.create_time_series(name=project_name, time_series=[series])
            logging.info("Metric written successfully on attempt %d", attempt)
            return True
        except Exception as e:
            logging.exception("Attempt %d failed to write metric: %s", attempt, e)
            if attempt < max_attempts:
                time.sleep(backoff)
                backoff *= 2
            else:
                logging.error("All %d attempts failed to write metric %s", max_attempts, metric_type)
                # Emit a structured fallback log so a logging-based metric can be created
                logging.info({
                    "fallback_metric": metric_type,
                    "value": value,
                    "note": "metric_write_failed; create logging-based metric from this log",
                    "project": project_id,
                })
                return False

def check_target(url: str) -> int:
    try:
        idt = fetch_id_token(url)
        headers = {"Authorization": f"Bearer {idt}"}
        r = requests.get(url, headers=headers, timeout=15)
        logging.info("Health check %s -> %s", url, r.status_code)
        return 1 if r.status_code < 400 else 0
    except Exception as e:
        logging.exception("Health check failed: %s", e)
        return 0

def main(event, context):
    project_id = os.environ.get("GCP_PROJECT") or os.environ.get("PROJECT_ID")
    if not project_id:
        try:
            _, project_id = google.auth.default()
        except Exception:
            project_id = None
    if not project_id:
        logging.error("GCP project not set in env and could not be detected via ADC")
        return
    if not TARGET_URL:
        logging.error("TARGET_URL env not set")
        return
    val = check_target(TARGET_URL)
    write_metric(project_id, METRIC_TYPE, val)
    logging.info("Wrote metric %s=%s", METRIC_TYPE, val)
