#!/usr/bin/env bash
set -euo pipefail

# AWS cleanup: stop active resources in an idempotent way.
# Respects DRY_RUN env var: if set to "true" no state-changing action is executed.

DRY_RUN=${DRY_RUN:-true}
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AWS_REGION="${AWS_REGION:-us-east-1}"
LOGFILE="${LOGFILE:-${REPO_ROOT}/logs/cleanup/cleanup-audit.jsonl}"
ERROR_FILE="${ERROR_FILE:-${REPO_ROOT}/logs/cleanup/cleanup-errors.jsonl}"

mkdir -p "$(dirname "$LOGFILE")"

log(){
  command -v jq >/dev/null 2>&1 || true
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg ts "$(date -u +%Y-%m-%dT%H:%M:%S.%6NZ)" --arg m "$1" '{timestamp:$ts,cloud:"aws",message:$m}' >> "$LOGFILE"
  else
    echo "$1" >> "$LOGFILE"
  fi
}

log_error(){
  local m="$1"
  log "ERROR: $m"
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg ts "$(date -u +%Y-%m-%dT%H:%M:%S.%6NZ)" --arg m "$m" '{timestamp:$ts,cloud:"aws",error:$m}' >> "$ERROR_FILE"
  else
    echo "ERROR: $m" >> "$ERROR_FILE"
  fi
}

run_mutation(){
  local description="$1"
  shift
  if [ "$DRY_RUN" = "true" ]; then
    echo "DRY-RUN: ${description}"
    log "dry_run ${description}"
    return 0
  fi
  if "$@"; then
    log "success ${description}"
  else
    log_error "failed ${description}"
  fi
}

echo "AWS cleanup invoked (dry-run=$DRY_RUN)"
log "aws_cleanup_invoked dry_run=$DRY_RUN region=$AWS_REGION"

if ! command -v aws >/dev/null 2>&1; then
  log "aws CLI not installed; skipping AWS cleanup"
  exit 0
fi

list_resources(){
  aws ec2 describe-instances --region "$AWS_REGION" --filters Name=instance-state-name,Values=running --query 'Reservations[].Instances[].{InstanceId:InstanceId,State:State.Name,Type:InstanceType}' --output table 2>/dev/null || true
  aws lambda list-functions --region "$AWS_REGION" --query 'Functions[].{FunctionName:FunctionName,Runtime:Runtime,LastModified:LastModified}' --output table 2>/dev/null || true
  aws ecs list-clusters --region "$AWS_REGION" --output text 2>/dev/null || true
}

stop_ec2_instances(){
  local ids
  ids=$(aws ec2 describe-instances --region "$AWS_REGION" --filters Name=instance-state-name,Values=running --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null || true)
  [ -z "$ids" ] && return 0
  run_mutation "aws stop ec2 instances ${ids}" aws ec2 stop-instances --region "$AWS_REGION" --instance-ids $ids
}

scale_ecs_services_to_zero(){
  local clusters
  clusters=$(aws ecs list-clusters --region "$AWS_REGION" --query 'clusterArns[]' --output text 2>/dev/null || true)
  [ -z "$clusters" ] && return 0
  local cluster
  for cluster in $clusters; do
    local services
    services=$(aws ecs list-services --region "$AWS_REGION" --cluster "$cluster" --query 'serviceArns[]' --output text 2>/dev/null || true)
    [ -z "$services" ] && continue
    local service
    for service in $services; do
      run_mutation "aws ecs desired-count=0 ${service}" aws ecs update-service --region "$AWS_REGION" --cluster "$cluster" --service "$service" --desired-count 0
    done
  done
}

if [ "$DRY_RUN" = "true" ]; then
  echo "DRY-RUN: listing AWS resources"
  list_resources
  log "aws_dry_run_listed_resources"
  exit 0
fi

echo "Performing AWS cleanup..."
log "aws_cleanup_started"

stop_ec2_instances
scale_ecs_services_to_zero

log "aws_cleanup_completed"
echo "AWS cleanup completed"
