#!/usr/bin/env bash
# Send a minimal OTLP span to a Splunk HEC endpoint using datastream.
# Requires SPLUNK_HEC_TOKEN and SPLUNK_HEC_ENDPOINT.
set -euo pipefail

if [ -z "${SPLUNK_HEC_TOKEN:-}" ] || [ -z "${SPLUNK_HEC_ENDPOINT:-}" ]; then
  echo "Splunk HEC token or endpoint not set; skipping Splunk send"
  exit 0
fi

ENDPOINT=${OTEL_EXPORTER_OTLP_ENDPOINT:-"$SPLUNK_HEC_ENDPOINT"}

cat <<'EOF' | curl -s -o /dev/null -w "%{http_code}\n" -X POST "$ENDPOINT" \
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
              "startTimeUnixNano": "$(date +%s%N)",
              "endTimeUnixNano": "$(($(date +%s%N) + 1000000))",
              "attributes": []
            }
          ]
        }
      ]
    }
  ]
}
EOF
