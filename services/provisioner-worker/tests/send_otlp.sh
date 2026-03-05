#!/usr/bin/env bash
# Simple test to POST a sample OTLP span to the configured endpoint
set -euo pipefail

ENDPOINT=${OTEL_EXPORTER_OTLP_ENDPOINT:-http://localhost:4318/v1/traces}

cat <<'EOF' | curl -s -o /dev/null -w "%{http_code}\n" -X POST "$ENDPOINT" \
  -H "Content-Type: application/json" \
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
              "traceId": "00000000000000000000000000000001",
              "spanId": "0000000000000002",
              "name": "test-span",
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

# curl exit code is printed above; ignore for CI
