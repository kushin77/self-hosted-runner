#!/usr/bin/env bash
set -euo pipefail
# Usage: run this on an admin host with kubeconfig and access to the cluster API
# It will create the ops namespace, create the gcp-sa-key k8s secret from a provided
# service-account key file, apply the CronJob manifest, run a one-off job and stream logs,
# then validate archives exist in S3.

KEY_PATH=${1:-/path/to/sa-key-milestone-organizer.json}
KUBECTL=${KUBECTL:-kubectl}
AWS_PROFILE=${AWS_PROFILE:-dev}
ARCHIVE_S3_BUCKET=${ARCHIVE_S3_BUCKET:-akushnir-milestones-20260312}
PREFIX=${ARCHIVE_PREFIX:-milestones-assignments}

echo "Using kubeconfig: ${KUBECONFIG:-$HOME/.kube/config}"
echo "Using SA key: $KEY_PATH"

if [ ! -f "$KEY_PATH" ]; then
  echo "ERROR: key file not found at $KEY_PATH" >&2
  exit 2
fi

echo "Ensure namespace 'ops' exists"
$KUBECTL create namespace ops --dry-run=client -o yaml | $KUBECTL apply -f -

echo "Create or replace k8s secret gcp-sa-key"
$KUBECTL -n ops delete secret gcp-sa-key --ignore-not-found || true
$KUBECTL -n ops create secret generic gcp-sa-key --from-file=key.json="$KEY_PATH"

echo "Apply CronJob manifest"
$KUBECTL apply -f k8s/milestone-organizer-cronjob.yaml --validate=false

echo "Triggering one-off job from CronJob"
JOBNAME="milestone-organizer-test-$(date +%s)"
$KUBECTL -n ops create job --from=cronjob/milestone-organizer "$JOBNAME"

echo "Waiting for pod..."
sleep 3
POD=$($KUBECTL -n ops get pods -l job-name="$JOBNAME" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -z "$POD" ]; then
  echo "No pod found for job yet; listing pods:"
  $KUBECTL -n ops get pods -o wide
  echo "Exiting; check job status manually"
  exit 1
fi

echo "Streaming logs from pod $POD"
$KUBECTL -n ops logs -f "$POD"

echo "Once job completes, verify S3 archival (list prefix):"
echo "aws --profile $AWS_PROFILE s3 ls s3://$ARCHIVE_S3_BUCKET/$PREFIX/"

echo "Done"
