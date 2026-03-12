#!/usr/bin/env bash
set -euo pipefail

# Operator script: deploy CronJob + ServiceAccount (Namespace created on first apply),
# trigger a one-off job, stream logs, and verify archival to S3.
# Usage: ./deploy/milestone-organizer-deploy-and-test.sh [--kubecontext CONTEXT] [--aws-profile PROFILE]

KUBE_CONTEXT=""
AWS_PROFILE=${AWS_PROFILE:-dev}
MANIFEST=k8s/milestone-organizer-cronjob.yaml
S3_BUCKET=${S3_BUCKET:-akushnir-milestones-20260312}
NAMESPACE=ops
TIMEOUT=${TIMEOUT:-300}

usage() {
  cat <<EOF
Usage: $0 [--kubecontext CONTEXT] [--aws-profile PROFILE] [--s3-bucket BUCKET]

Deploys the milestone-organizer CronJob and runs a test job.

Options:
  --kubecontext CONTEXT   Use specified kubecontext (optional)
  --aws-profile PROFILE   AWS profile for S3 verification (default: $AWS_PROFILE)
  --s3-bucket BUCKET      S3 bucket to verify uploads (default: $S3_BUCKET)
  --help                  Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --kubecontext) KUBE_CONTEXT="$2"; shift 2 ;;
    --aws-profile) AWS_PROFILE="$2"; shift 2 ;;
    --s3-bucket) S3_BUCKET="$2"; shift 2 ;;
    --help) usage; exit 0 ;;
    *) echo "Unknown arg: $1"; usage; exit 2 ;;
  esac
done

kubectl_cmd=(kubectl)
if [ -n "$KUBE_CONTEXT" ]; then
  kubectl_cmd+=(--context "$KUBE_CONTEXT")
fi

echo "Using kubecontext: ${KUBE_CONTEXT:-(default)}"
echo "Using AWS profile: $AWS_PROFILE"
echo "Manifest: $MANIFEST"

# confirm kubectl works
echo "Checking Kubernetes API access..."
if ! "${kubectl_cmd[@]}" version --short >/dev/null 2>&1; then
  echo "ERROR: kubectl cannot reach cluster. Ensure kubeconfig and network access." >&2
  exit 3
fi

# Apply manifests (Namespace + SA + CronJob in single file)
echo "Applying manifest $MANIFEST"
"${kubectl_cmd[@]}" apply -f "$MANIFEST"

# Ensure namespace exists
echo "Ensuring namespace $NAMESPACE exists"
"${kubectl_cmd[@]}" get namespace "$NAMESPACE" >/dev/null 2>&1 || "${kubectl_cmd[@]}" create namespace "$NAMESPACE"

# Wait for cronjob to appear
echo "Waiting for CronJob to be recognized..."
end=$((SECONDS + 60))
while [ $SECONDS -lt $end ]; do
  if "${kubectl_cmd[@]}" -n "$NAMESPACE" get cronjob milestone-organizer >/dev/null 2>&1; then
    echo "CronJob present"
    break
  fi
  sleep 2
done

# Create a one-off job from the CronJob
JOB_NAME="milestone-organizer-test-$(date -u +%Y%m%dT%H%M%SZ)"
echo "Creating one-off job: $JOB_NAME"
"${kubectl_cmd[@]}" -n "$NAMESPACE" create job --from=cronjob/milestone-organizer "$JOB_NAME"

# Wait for pod to appear
echo "Waiting for Pod to start (timeout=${TIMEOUT}s)..."
start=$SECONDS
POD_NAME=""
while [ $((SECONDS - start)) -lt $TIMEOUT ]; do
  POD_NAME=$("${kubectl_cmd[@]}" -n "$NAMESPACE" get pods -l job-name="$JOB_NAME" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  if [ -n "$POD_NAME" ]; then
    echo "Found pod: $POD_NAME"
    break
  fi
  sleep 2
done

if [ -z "$POD_NAME" ]; then
  echo "ERROR: Pod did not start within ${TIMEOUT}s" >&2
  exit 4
fi

# Stream logs until pod completes (or CTRL-C)
echo "Streaming logs from pod $POD_NAME (follow until completion)"
"${kubectl_cmd[@]}" -n "$NAMESPACE" logs -f "$POD_NAME"

# After completion, verify S3 artifacts
echo "Verifying S3 archival in s3://$S3_BUCKET/milestones-assignments/"
if aws --profile "$AWS_PROFILE" s3 ls "s3://$S3_BUCKET/milestones-assignments/" --recursive >/dev/null 2>&1; then
  echo "S3 objects found:" 
  aws --profile "$AWS_PROFILE" s3 ls "s3://$S3_BUCKET/milestones-assignments/" --recursive | sed -n '1,200p'
  echo "Archival verification: OK"
else
  echo "WARNING: No objects found in s3://$S3_BUCKET/milestones-assignments/. Verify the pod ran and had S3 access." >&2
  exit 5
fi

echo "Deployment and test completed successfully."
exit 0
