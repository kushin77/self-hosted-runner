#!/usr/bin/env bash
set -euo pipefail

# Graceful shutdown handler for provisioner-worker HA
# Called by Kubernetes preStop hook during pod termination
# Requeues in-flight jobs back to Redis queue and waits for completion

SHUTDOWN_TIMEOUT=${WORKER_SHUTDOWN_TIMEOUT:-60}
REDIS_URL=${PROVISIONER_REDIS_URL:-redis://localhost:6379}
HEALTH_CHECK_PORT=${HEALTH_CHECK_PORT:-8081}

echo "=== Graceful Shutdown Started ==="
echo "Timeout: ${SHUTDOWN_TIMEOUT}s"

# Step 1: Stop accepting new jobs (signal readiness unhealthy)
echo "Step 1: Stopping acceptance of new jobs..."
kill -SIGUSR1 1 2>/dev/null || true  # Signal parent process to stop accepting
sleep 2

# Step 2: Finish processing current jobs (wait up to SHUTDOWN_TIMEOUT)
echo "Step 2: Finishing current jobs (max ${SHUTDOWN_TIMEOUT}s)..."
start_time=$(date +%s)
while true; do
  current_time=$(date +%s)
  elapsed=$((current_time - start_time))
  
  if [ $elapsed -ge $SHUTDOWN_TIMEOUT ]; then
    echo "⚠ Shutdown timeout reached; force-requeuing remaining jobs"
    break
  fi
  
  # Check if any jobs still in-flight
  jobs_in_flight=$(redis-cli -u "$REDIS_URL" HLEN "provisioner:jobs:active" 2>/dev/null || echo "1")
  
  if [ "$jobs_in_flight" -eq 0 ]; then
    echo "✓ No jobs in-flight; safe to shutdown"
    break
  fi
  
  echo "  Jobs in-flight: $jobs_in_flight; waiting..."
  sleep 2
done

# Step 3: Requeue any pending jobs back to main queue
echo "Step 3: Requeuing incomplete jobs..."
requeue_error=0
for job_id in $(redis-cli -u "$REDIS_URL" HKEYS "provisioner:jobs:active" 2>/dev/null || true); do
  job_data=$(redis-cli -u "$REDIS_URL" HGET "provisioner:jobs:active" "$job_id" 2>/dev/null)
  if [ -n "$job_data" ]; then
    # Push back to main queue
    redis-cli -u "$REDIS_URL" RPUSH "provisioner:jobs:queue" "$job_data" >/dev/null 2>&1 || {
      echo "⚠ Failed to requeue job $job_id"
      requeue_error=1
    }
    # Remove from active
    redis-cli -u "$REDIS_URL" HDEL "provisioner:jobs:active" "$job_id" >/dev/null 2>&1
  fi
done

if [ $requeue_error -eq 0 ]; then
  echo "✓ All jobs requeued successfully"
fi

# Step 4: Log shutdown event
echo "Step 4: Logging shutdown event..."
POD_NAME=$(hostname)
POD_NAMESPACE=${POD_NAMESPACE:-provisioner-system}
echo "Pod ${POD_NAME} in ${POD_NAMESPACE} shutting down gracefully at $(date -u +'%Y-%m-%dT%H:%M:%SZ')" | \
  logger -t provisioner-worker-shutdown 2>/dev/null || true

# Step 5: Close Vault client (revoke token)
echo "Step 5: Closing Vault session..."
if command -v vault >/dev/null && [ -n "${VAULT_TOKEN:-}" ]; then
  vault token revoke 2>/dev/null || true
fi

echo "=== Graceful Shutdown Completed ==="
exit 0
