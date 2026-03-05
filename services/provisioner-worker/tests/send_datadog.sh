#!/usr/bin/env bash
# Send a minimal OTLP span to a Datadog intake via OTLP/HTTP.
# Requires DATADOG_API_KEY environment variable; otherwise skips.
set -euo pipefail

if [ -z "${DATADOG_API_KEY:-}" ]; then
  echo "DATADOG_API_KEY not set; skipping Datadog send"
  exit 0
fi

ENDPOINT=${OTEL_EXPORTER_OTLP_ENDPOINT:-"https://otlp.datadoghq.com/v1/traces"}

cat <<'EOF' | curl -s -o /dev/null -w "%{http_code}\n" -X POST "$ENDPOINT" \
  -H "Content-Type: application/json" \
  -H "DD-API-KEY: $DATADOG_API_KEY" \
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
              "traceId": "00000000000000000000000000000002",
              "spanId": "0000000000000003",
              "name": "dd-test-span",
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
