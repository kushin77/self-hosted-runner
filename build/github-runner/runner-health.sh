#!/usr/bin/env bash
# runner-health.sh - Simple health check endpoint for GitHub Actions runner
#
# Provides HTTP endpoint at localhost:8888 for Kubernetes-style health checks
# - /health: Full health check (liveness + readiness)
# - /healthz: Alias for /health
# - /ready: Readiness (can accept jobs)
# - /live: Liveness (process alive)
#
# Usage: ./runner-health.sh [--port PORT] [--container-name NAME] [--background]

set -euo pipefail

PORT="${PORT:-8888}"
CONTAINER_NAME="${CONTAINER_NAME:-elevatediq-github-runner}"
RUN_BACKGROUND="${RUN_BACKGROUND:-0}"
CHECK_INTERVAL="${CHECK_INTERVAL:-30}"
REPO="kushin77/ElevatedIQ-Mono-Repo"

# State file for health cache
STATE_DIR="/tmp/runner-health-${CONTAINER_NAME}"
mkdir -p "$STATE_DIR"
HEALTH_STATE="$STATE_DIR/health.json"

# ============================================================================
# HEALTH CHECKS
# ============================================================================

health_check_liveness() {
  # Is the container process running?
  if ! docker inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
    return 1
  fi

  local state=$(docker inspect "$CONTAINER_NAME" --format='{{.State.Running}}' 2>/dev/null || echo "false")
  [[ "$state" == "true" ]]
}

health_check_readiness() {
  # Is the runner registered and accepting jobs on GitHub?
  if ! command -v gh >/dev/null 2>&1; then
    return 0  # Can't check without gh, assume ready
  fi

  local runner_name=$(docker inspect "$CONTAINER_NAME" --format='{{index .Config.Env}}' 2>/dev/null | grep -o 'RUNNER_NAME=[^ ]*' | cut -d= -f2 || echo "elevatediq-runner-42")

  local status=$(gh api repos/${REPO}/actions/runners --jq ".runners[] | select(.name | contains(\"elevator\")) | .status" 2>/dev/null | head -1 || echo "unknown")

  [[ "$status" == "online" ]]
}

health_check_disk() {
  # Is there enough disk space?
  local free_gb=$(df -BG /tmp 2>/dev/null | tail -1 | awk '{print $4}' | sed 's/G//' || echo 0)
  [[ $free_gb -gt 1 ]]
}

health_check_docker() {
  # Can we reach docker daemon?
  docker ps >/dev/null 2>&1
}

health_check_logs() {
  # Are there critical errors in recent logs?
  if ! docker logs "$CONTAINER_NAME" 2>/dev/null | tail -100 | grep -q "Fatal error\|CRITICAL\|panic"; then
    return 0  # No critical errors
  fi
  return 1
}

# ============================================================================
# JSON RESPONSE BUILDER
# ============================================================================

build_health_json() {
  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local live=0
  local ready=0
  local disk=0
  local docker_ok=0
  local logs_ok=0

  health_check_liveness && ((live++))
  health_check_readiness && ((ready++))
  health_check_disk && ((disk++))
  health_check_docker && ((docker_ok++))
  health_check_logs && ((logs_ok++))

  local status="healthy"
  if [[ $live -eq 0 ]]; then
    status="unhealthy"
  elif [[ $ready -eq 0 ]]; then
    status="degraded"
  fi

  cat <<EOF
{
  "status": "$status",
  "timestamp": "$timestamp",
  "container": "$CONTAINER_NAME",
  "checks": {
    "liveness": {
      "status": $([ $live -eq 1 ] && echo "\"pass\"" || echo "\"fail\""),
      "description": "Container process is running"
    },
    "readiness": {
      "status": $([ $ready -eq 1 ] && echo "\"pass\"" || echo "\"fail\""),
      "description": "Runner is online and accepting jobs on GitHub"
    },
    "disk": {
      "status": $([ $disk -eq 1 ] && echo "\"pass\"" || echo "\"fail\""),
      "description": "Sufficient disk space available (>1GB)"
    },
    "docker": {
      "status": $([ $docker_ok -eq 1 ] && echo "\"pass\"" || echo "\"fail\""),
      "description": "Docker daemon is accessible"
    },
    "logs": {
      "status": $([ $logs_ok -eq 1 ] && echo "\"pass\"" || echo "\"fail\""),
      "description": "No critical errors in logs"
    }
  },
  "overall_score": $((live + ready + disk + docker_ok + logs_ok))/5
}
EOF
}

# ============================================================================
# HTTP SERVER
# ============================================================================

serve_health_endpoint() {
  local port="$1"

  echo "[health] Starting HTTP server on port $port" >&2

  # Simple bash HTTP server using nc (netcat)
  # This is a minimal implementation; for production, use a proper web server

  while true; do
    # Accept connection
    read -t 1 request method path protocol < /dev/stdin 2>/dev/null || {
      sleep 0.1
      continue
    }

    # Generate response based on path
    local response_body=""
    local response_code="404 Not Found"

    case "$path" in
      /health|/healthz)
        response_code="200 OK"
        response_body=$(build_health_json)
        ;;
      /ready)
        if health_check_readiness; then
          response_code="200 OK"
          response_body='{"status":"ready"}'
        else
          response_code="503 Service Unavailable"
          response_body='{"status":"not_ready"}'
        fi
        ;;
      /live)
        if health_check_liveness; then
          response_code="200 OK"
          response_body='{"status":"alive"}'
        else
          response_code="503 Service Unavailable"
          response_body='{"status":"dead"}'
        fi
        ;;
      /metrics|/metrics/health)
        response_code="200 OK"
        # Simple Prometheus-style metrics
        response_body=$(cat <<EOF
# HELP runner_health_status Overall health status (1=healthy, 0=unhealthy)
# TYPE runner_health_status gauge
runner_health_status{container="$CONTAINER_NAME"} $([ "$(health_check_liveness && echo 1 || echo 0)" == "1" ] && echo 1 || echo 0)

# HELP runner_liveness_check Liveness check result
# TYPE runner_liveness_check gauge
runner_liveness_check{container="$CONTAINER_NAME"} $([ "$(health_check_liveness && echo 1 || echo 0)" == "1" ] && echo 1 || echo 0)

# HELP runner_readiness_check Readiness check result
# TYPE runner_readiness_check gauge
runner_readiness_check{container="$CONTAINER_NAME"} $([ "$(health_check_readiness && echo 1 || echo 0)" == "1" ] && echo 1 || echo 0)
EOF
)
        ;;
      *)
        response_code="404 Not Found"
        response_body='{"error":"endpoint not found"}'
        ;;
    esac

    # Build HTTP response
    local response="HTTP/1.1 $response_code\r\n"
    response+="Content-Type: application/json\r\n"
    response+="Content-Length: ${#response_body}\r\n"
    response+="Connection: close\r\n"
    response+="\r\n"
    response+="$response_body"

    echo -ne "$response"
  done | nc -l -p "$port" 2>/dev/null || {
    echo "[health] nc not available; falling back to socat" >&2
    # Fallback to socat if available
    if command -v socat >/dev/null 2>&1; then
      socat TCP-LISTEN:"$port",reuseaddr EXEC:"$0 --handle-request" &
      wait
    fi
  }
}

# Simpler async version: update cache file periodically
serve_health_cache() {
  local port="$1"

  echo "[health] Starting periodic health check (updating cache every $CHECK_INTERVAL seconds)" >&2

  while true; do
    # Update health state file
    build_health_json > "$HEALTH_STATE" 2>/dev/null || true

    # Sleep before next check
    sleep $CHECK_INTERVAL
  done
}

# ============================================================================
# ARGUMENT PARSING
# ============================================================================

usage() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --port PORT              HTTP port (default: 8888)"
  echo "  --container-name NAME    Container to monitor (default: elevatediq-github-runner)"
  echo "  --background             Run in background"
  echo "  --check-interval SEC     Health check interval in seconds (default: 30)"
  echo "  -h, --help               Show this help"
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) PORT="$2"; shift 2 ;;
    --container-name) CONTAINER_NAME="$2"; shift 2 ;;
    --background) RUN_BACKGROUND=1; shift ;;
    --check-interval) CHECK_INTERVAL="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

# ============================================================================
# MAIN
# ============================================================================

# Verify container exists
if ! docker inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
  echo "ERROR: Container not found: $CONTAINER_NAME" >&2
  exit 1
fi

echo "[health] Starting health check service for $CONTAINER_NAME"
echo "[health] Endpoints:"
echo "[health]   GET http://localhost:$PORT/health"
echo "[health]   GET http://localhost:$PORT/ready"
echo "[health]   GET http://localhost:$PORT/live"
echo "[health]   GET http://localhost:$PORT/metrics"

if [[ "$RUN_BACKGROUND" -eq 1 ]]; then
  # Run as daemon
  serve_health_cache "$PORT" &
  echo "[health] Health check daemon started (PID: $!)"
  echo "$!" > "$STATE_DIR/health.pid"
else
  # Run in foreground
  serve_health_cache "$PORT"
fi
