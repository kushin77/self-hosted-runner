#!/usr/bin/env bash
# Send a minimal OTLP span to a Splunk HEC endpoint using datastream.
# Requires SPLUNK_HEC_TOKEN and SPLUNK_HEC_ENDPOINT.
set -euo pipefail

if [ -z "${SPLUNK_HEC_TOKEN:-}" ] || [ -z "${SPLUNK_HEC_ENDPOINT:-}" ]; then
  echo "Splunk HEC token or endpoint not set; skipping Splunk send"
  exit 0
fi

ENDPOINT=${OTEL_EXPORTER_OTLP_ENDPOINT:-"$SPLUNK_HEC_ENDPOINT"}

attempt=0
max_attempts=3
backoff=1
while true; do
  attempt=$((attempt+1))
  echo "Splunk send attempt $attempt/$max_attempts -> $ENDPOINT"
  HTTP_CODE=$(cat <<EOF | curl -s -o /dev/null -w "%{http_code}" -X POST "$ENDPOINT" \
    -H "Content-Type: application/json" \
    -H "Authorization: Splunk $SPLUNK_HEC_TOKEN" \
    --data-binary @-
{
  "resourceSpans": [
    {
      "resource": {"attributes": [{"key":"service.name","value":{"stringValue":"test"}}]},
      "scopeSpans": [
        {
          "scope": {"name":"provisioner-worker"},
          "spans": [
            {
              "traceId": "00000000000000000000000000000003",
              "spanId": "0000000000000004",
              "name": "splunk-test-span",
              "kind": 1,
              "startTimeUnixNano": $(date +%s%N),
              "endTimeUnixNano": $(($(date +%s%N) + 1000000)),
              "attributes": []
            }
          ]
        }
      ]
    }
  ]
}
EOF
  ) || HTTP_CODE=000

  if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "202" ]; then
    echo "Splunk send successful (HTTP $HTTP_CODE)"
    exit 0
  fi

  if [ "$attempt" -ge "$max_attempts" ]; then
    echo "Splunk send failed after $attempt attempts (HTTP $HTTP_CODE)"
    exit 2
  fi

  echo "Splunk send returned $HTTP_CODE; retrying in $backoff seconds..."
  sleep "$backoff"
  backoff=$((backoff * 2))
done
