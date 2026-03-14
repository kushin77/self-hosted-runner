#!/usr/bin/env bash
set -euo pipefail

# Pre-Flight Infrastructure Audit - read-only inventory collector
# Produces JSON summary files for on-prem, GCP, AWS, and Azure.

OUTDIR="artifacts/infra-audit-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$OUTDIR"

echo "Starting pre-flight infrastructure audit; output -> $OUTDIR"

echo "Collecting local/docker info..."
jq -n --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{collected:$ts,source:"on-prem"}' > "$OUTDIR/onprem-meta.json"
if command -v docker >/dev/null 2>&1; then
  docker ps --format '{{json .}}' | jq -s '.' > "$OUTDIR/docker-containers.json" || true
fi

if command -v kubectl >/dev/null 2>&1; then
  kubectl config view --minify -o json > "$OUTDIR/kube-config.json" || true
  kubectl get namespaces -o json > "$OUTDIR/kube-namespaces.json" || true
fi

echo "Collecting GCP inventory..."
if command -v gcloud >/dev/null 2>&1; then
  gcloud projects list --format=json > "$OUTDIR/gcp-projects.json" || true
  gcloud compute instances list --format=json > "$OUTDIR/gcp-instances.json" || true
  gcloud container clusters list --format=json > "$OUTDIR/gke-clusters.json" || true
  gcloud storage buckets list --format=json > "$OUTDIR/gcp-buckets.json" || true
fi

echo "Collecting AWS inventory..."
if command -v aws >/dev/null 2>&1; then
  aws sts get-caller-identity --output json > "$OUTDIR/aws-caller.json" || true
  aws ec2 describe-instances --output json > "$OUTDIR/aws-ec2-instances.json" || true
  aws s3api list-buckets --output json > "$OUTDIR/aws-s3-buckets.json" || true
  aws eks list-clusters --output json > "$OUTDIR/aws-eks-clusters.json" || true
fi

echo "Collecting Azure inventory..."
if command -v az >/dev/null 2>&1; then
  az account show --output json > "$OUTDIR/azure-account.json" || true
  az vm list --output json > "$OUTDIR/azure-vms.json" || true
  az aks list --output json > "$OUTDIR/azure-aks.json" || true
  az storage account list --output json > "$OUTDIR/azure-storage.json" || true
fi

echo "Collecting Terraform state references (if present)..."
find . -maxdepth 3 -name 'terraform.tfstate*' -print -exec cp -v --parents {} "$OUTDIR" \; || true

echo "Audit complete. Outputs:"
ls -la "$OUTDIR"

echo "TIP: review artifacts in $OUTDIR and commit the non-sensitive inventory outputs to your audit repo or attach to the epic." 
