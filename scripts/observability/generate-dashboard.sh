#!/usr/bin/env bash
# Simple stub to output a basic Grafana dashboard JSON template
cat <<'EOF'
{
  "dashboard": {
    "id": null,
    "title": "SERVICE_NAME Dashboard",
    "panels": []
  },
  "overwrite": false
}
EOF
