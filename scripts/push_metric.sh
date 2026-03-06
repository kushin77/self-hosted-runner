#!/bin/bash
set -e

# Usage: push_metric.sh <pushgateway_url> [metric_name] [value]
# If PUSHGATEWAY_URL env var is set, it will be used instead of the first arg.

PUSHGATEWAY_URL="${PUSHGATEWAY_URL:-$1}"
METRIC_NAME="${2:-runner_reprovision_total}"
VALUE="${3:-1}"
HOST="$(hostname -s)"
JOB="runner-health"

if [ -z "$PUSHGATEWAY_URL" ]; then
  echo "PUSHGATEWAY_URL not set; skipping metric push"
  exit 0
fi

cat <<EOF | curl --silent --show-error --fail --data-binary @- "${PUSHGATEWAY_URL}/metrics/job/${JOB}/instance/${HOST}"
# TYPE ${METRIC_NAME} counter
${METRIC_NAME}{host="${HOST}"} ${VALUE}
EOF

echo "Pushed metric ${METRIC_NAME}=${VALUE} to ${PUSHGATEWAY_URL}"
