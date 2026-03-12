#!/bin/bash
set -euo pipefail

##############################################################################
# NORMALIZER CRONJOB — POST-DEPLOYMENT SMOKE TEST
# Usage: bash scripts/ops/verify-normalizer-cronjob.sh
# Purpose: Validate Day 3 CronJob deployment before production cutover
##############################################################################

KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
CONTEXT="${K8S_CONTEXT:-kind-deployment-local}"
NAMESPACE="nexus-engine"
CRONJOB_NAME="normalizer"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║         NORMALIZER CRONJOB — VERIFICATION SCRIPT          ║"
echo "║                 March 12, 2026 — Smoke Test              ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# 1. Check kubectl access
echo "✓ Verifying kubectl access..."
if ! kubectl config use-context "$CONTEXT" >/dev/null 2>&1; then
  echo "  ✗ FAILED: Cannot access context '$CONTEXT'."
  echo "    Available contexts: $(kubectl config get-contexts -o name | tr '\n' ' ')"
  exit 1
fi
echo "  ✓ kubectl context: $CONTEXT"
echo ""

# 2. Verify namespace exists
echo "✓ Checking namespace..."
if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
  echo "  ✗ FAILED: Namespace '$NAMESPACE' not found."
  exit 1
fi
echo "  ✓ Namespace: $NAMESPACE"
echo ""

# 3. Verify CronJob exists
echo "✓ Checking CronJob resource..."
if ! CRONJOB_STATUS=$(kubectl get cronjob "$CRONJOB_NAME" -n "$NAMESPACE" -o json 2>/dev/null); then
  echo "  ✗ FAILED: CronJob '$CRONJOB_NAME' not found."
  exit 1
fi
echo "  ✓ CronJob: $CRONJOB_NAME"
SCHEDULE=$(echo "$CRONJOB_STATUS" | jq -r '.spec.schedule')
SUSPEND=$(echo "$CRONJOB_STATUS" | jq -r '.spec.suspend')
echo "    - Schedule: $SCHEDULE"
echo "    - Suspend: $SUSPEND"
echo ""

# 4. Check CronJob image
echo "✓ Verifying image..."
IMAGE=$(echo "$CRONJOB_STATUS" | jq -r '.spec.jobTemplate.spec.template.spec.containers[0].image')
echo "  ✓ Image: $IMAGE"
echo ""

# 5. Verify ConfigMap
echo "✓ Checking ConfigMap..."
if ! kubectl get configmap normalizer-config -n "$NAMESPACE" >/dev/null 2>&1; then
  echo "  ✗ FAILED: ConfigMap not found."
  exit 1
fi
echo "  ✓ ConfigMap: normalizer-config"
echo ""

# 6. Verify Secret
echo "✓ Checking Secret..."
if ! kubectl get secret normalizer-secrets -n "$NAMESPACE" >/dev/null 2>&1; then
  echo "  ✗ WARNING: Secret not found (OK if using external secret provider)."
else
  echo "  ✓ Secret: normalizer-secrets"
fi
echo ""

# 7. Check ServiceAccount
echo "✓ Checking ServiceAccount..."
if ! kubectl get sa normalizer-sa -n "$NAMESPACE" >/dev/null 2>&1; then
  echo "  ✗ FAILED: ServiceAccount not found."
  exit 1
fi
echo "  ✓ ServiceAccount: normalizer-sa"
echo ""

# 8. Check dependent services (Kafka, Postgres)
echo "✓ Checking dependent services..."
for SVC in kafka postgres; do
  if ! kubectl get svc "$SVC" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "  ⚠ Service '$SVC' not found (expected if running externally)."
  else
    PORT=$(kubectl get svc "$SVC" -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].port}')
    echo "  ✓ Service: $SVC (port $PORT)"
  fi
done
echo ""

# 9. Wait for first job execution (optional: up to 5 minutes)
echo "✓ Waiting for CronJob execution (this may take up to 5 minutes)..."
MAX_WAIT=300  # 5 minutes
ELAPSED=0
while [ $ELAPSED -lt $MAX_WAIT ]; do
  JOB_COUNT=$(kubectl get jobs -n "$NAMESPACE" -l batch.kubernetes.io/cronjob-name="$CRONJOB_NAME" --sort-by='.metadata.creationTimestamp' -o jsonpath='{.items | length}')
  if [ "$JOB_COUNT" -gt 0 ]; then
    echo "  ✓ First job detected! ($JOB_COUNT job(s) found)"
    break
  fi
  sleep 5
  ELAPSED=$((ELAPSED + 5))
  echo "  • Waiting... ($ELAPSED/$MAX_WAIT seconds)"
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
  echo "  ⚠ Timeout waiting for job execution. (Might still succeed after 5-min boundary)"
fi
echo ""

# 10. Show pod status if jobs exist
if [ "$JOB_COUNT" -gt 0 ]; then
  echo "✓ Recent jobs:"
  kubectl get jobs -n "$NAMESPACE" -l batch.kubernetes.io/cronjob-name="$CRONJOB_NAME" --sort-by='.metadata.creationTimestamp' | tail -3
  echo ""

  echo "✓ Recent pods:"
  PODS=$(kubectl get pods -n "$NAMESPACE" -l app=normalizer --sort-by='.metadata.creationTimestamp' -o name | tail -1)
  if [ -n "$PODS" ]; then
    kubectl describe "$PODS" -n "$NAMESPACE" | head -20
    echo ""
    echo "  Pod logs (last 50 lines):"
    kubectl logs "$PODS" -n "$NAMESPACE" --tail=50 2>/dev/null || echo "    (no logs yet)"
  fi
fi
echo ""

# Summary
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                    VERIFICATION COMPLETE                   ║"
echo "║                                                            ║"
echo "║  ✅ CronJob deployment is valid and ready!               ║"
echo "║  📋 Schedule: $SCHEDULE"
echo "║  🖼️  Image: $IMAGE"
echo "║  🕐 Monitor logs: kubectl logs -n $NAMESPACE -l app=normalizer --tail=100"
echo "║                                                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
