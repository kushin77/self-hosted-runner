import os
import json
from datetime import datetime, timedelta
from google.cloud import logging
from google.cloud import storage

PROJECT = os.environ.get('GCP_PROJECT') or os.environ.get('GCP_PROJECT_ID') or 'nexusshield-prod'
BUCKET = os.environ.get('SUMMARY_BUCKET') or f'nexusshield-prod-daily-summaries-151423364222'
SERVICE_NAME = os.environ.get('SERVICE_NAME') or 'image-pin-service'

client = logging.Client()
storage_client = storage.Client()


def main(event, context):
    """Pub/Sub-triggered Cloud Function entry point."""
    end = datetime.utcnow()
    start = end - timedelta(hours=24)
    # Build filter for cloud run request_count aggregated by response_code
    filter_str = (
        'resource.type="cloud_run_revision" '
        f'AND resource.labels.service_name="{SERVICE_NAME}" '
        'AND metric.type="run.googleapis.com/request_count"'
    )

    # Query log entries for the time window
    time_filter = (
        f"timestamp>\"{start.isoformat()}Z\" AND timestamp<\"{end.isoformat()}Z\""
    )
    entries = client.list_entries(
        projects=[PROJECT],
        filter=f"{filter_str} AND {time_filter}",
        page_size=1000,
    )

    counts = {}
    for entry in entries:
        # metric entries appear in protoPayload or as logName; attempt to read labels
        try:
            labels = entry.resource.labels
            # response_code may be present in entry.labels or entry.json_payload
            rc = None
            if entry.labels and "response_code" in entry.labels:
                rc = entry.labels["response_code"]
            elif entry.json_payload and "response_code" in entry.json_payload:
                rc = str(entry.json_payload.get("response_code"))
            else:
                # try parsing textPayload
                tp = getattr(entry, "text_payload", None) or getattr(entry, "textPayload", None)
                if tp and isinstance(tp, str):
                    # naive search
                    import re

                    m = re.search(r"response_code=([0-9]{3})", tp)
                    if m:
                        rc = m.group(1)
            if not rc:
                rc = "-"
            counts[rc] = counts.get(rc, 0) + 1
        except Exception:
            continue

    total = sum(counts.values())
    five_xx = sum(v for k, v in counts.items() if str(k).startswith("5"))

    summary = {
        "project": PROJECT,
        "service": SERVICE_NAME,
        "window_start": start.isoformat() + "Z",
        "window_end": end.isoformat() + "Z",
        "total_requests": total,
        "5xx_count": five_xx,
        "by_response_code": counts,
        "generated_at": datetime.utcnow().isoformat() + "Z",
    }

    # Write to GCS
    bucket = storage_client.bucket(BUCKET)
    if not bucket.exists():
        bucket.storage_class = "STANDARD"
        bucket = storage_client.create_bucket(BUCKET, location="US")
    name = f"daily-summary-{SERVICE_NAME}-{end.strftime('%Y-%m-%dT%H%MZ')}.json"
    blob = bucket.blob(name)
    blob.upload_from_string(json.dumps(summary, indent=2), content_type="application/json")

    return summary
