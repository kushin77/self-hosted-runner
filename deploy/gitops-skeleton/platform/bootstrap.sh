#!/usr/bin/env bash
set -euo pipefail

echo "Bootstrap GitOps platform skeleton"

echo "1) Apply Tekton (cluster)"
echo "kubectl apply -f deploy/gitops-skeleton/platform/tekton/"

echo "2) Apply ArgoCD"
echo "kubectl apply -f deploy/gitops-skeleton/platform/argocd/"

echo "3) Apply OPA/Gatekeeper"
echo "kubectl apply -f deploy/gitops-skeleton/platform/opa/"

echo "4) Apply Observability stack (Prometheus, OTel, Loki, Jaeger)"
echo "kubectl apply -f deploy/gitops-skeleton/platform/observability/"

echo "After platform components are installed, connect ArgoCD to GitOps repos and synchronize clusters."
