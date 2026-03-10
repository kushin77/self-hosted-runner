#!/usr/bin/env bash
set -euo pipefail

# OpenTelemetry Integration for Distributed Tracing
# Provides end-to-end visibility into job execution across runners
#
# Features:
#   - Distributed trace collection (job → runner → task layers)
#   - Span correlation for multi-runner jobs
#   - Flamegraph analysis for bottleneck identification
#   - Integration with Jaeger/OpenTelemetry Collector

OTEL_COLLECTOR_ENDPOINT="${OTEL_COLLECTOR_ENDPOINT:-http://localhost:4317}"
OTEL_EXPORTER_OTLP_PROTOCOL="${OTEL_EXPORTER_OTLP_PROTOCOL:-grpc}"
SERVICE_NAME="${SERVICE_NAME:-github-actions-runner}"
TRACE_SAMPLE_RATE="${TRACE_SAMPLE_RATE:-0.1}"
TRACE_LOG_DIR="${TRACE_LOG_DIR:-/var/log/traces}"

mkdir -p "$TRACE_LOG_DIR"

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

error() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
  exit 1
}

# Initialize trace context (new trace for each job)
init_trace_context() {
  local job_id="$1"
  local repo="$2"
  
  # Generate trace ID (W3C format: 32 hex chars)
  local trace_id=$(head -c 16 /dev/urandom | xxd -p)
  
  # Generate span ID for root span (16 hex chars)
  local root_span_id=$(head -c 8 /dev/urandom | xxd -p)
  
  # Export context for child processes
  export TRACE_ID="$trace_id"
  export PARENT_SPAN_ID="$root_span_id"
  export JOB_ID="$job_id"
  export REPOSITORY="$repo"
  
  # Write context file for cross-process access
  cat > "${TRACE_LOG_DIR}/${job_id}.context" <<EOF
TRACE_ID=$trace_id
PARENT_SPAN_ID=$root_span_id
JOB_ID=$job_id
REPOSITORY=$repo
START_TIME=$(date +%s%N)
EOF
  
  log "📊 Trace initialized for job $job_id: trace_id=$trace_id"
  return 0
}

# Create a span within trace context
emit_span() {
  local span_name="$1"
  local span_status="${2:-OK}"
  local span_duration_ms="${3:-0}"
  
  [ -n "${TRACE_ID:-}" ] || error "No active trace context (init_trace_context not called)"
  
  # Generate span ID
  local span_id=$(head -c 8 /dev/urandom | xxd -p)
  
  # Construct OTLP JSON (simplified)
  local trace_json=$(cat <<EOF
{
  "resourceSpans": [{
    "resource": {
      "attributes": [
        { "key": "service.name", "value": { "stringValue": "$SERVICE_NAME" } },
        { "key": "host.name", "value": { "stringValue": "$(hostname)" } },
        { "key": "process.pid", "value": { "intValue": $$ } }
      ]
    },
    "scopeSpans": [{
      "scope": { "name": "github-actions-runner", "version": "1.0.0" },
      "spans": [{
        "traceId": "$TRACE_ID",
        "spanId": "$span_id",
        "parentSpanId": "${PARENT_SPAN_ID:-}",
        "name": "$span_name",
        "kind": "SPAN_KIND_INTERNAL",
        "startTimeUnixNano": $(($(date +%s%N))),
        "endTimeUnixNano": $(($(date +%s%N) + span_duration_ms * 1000000)),
        "status": {
          "code": "STATUS_CODE_OK",
          "message": "$span_status"
        },
        "attributes": [
          { "key": "repository", "value": { "stringValue": "${REPOSITORY:-}" } },
          { "key": "job_id", "value": { "stringValue": "${JOB_ID:-}" } }
        ]
      }]
    }]
  }]
}
EOF
)
  
  # Send to OTLP collector
  if command -v curl &> /dev/null; then
    curl -s -X POST \
      -H "Content-Type: application/json" \
      "$OTEL_COLLECTOR_ENDPOINT/v1/traces" \
      -d "$trace_json" 2>/dev/null || true
  fi
  
  # Log locally for offline analysis
  echo "$trace_json" >> "${TRACE_LOG_DIR}/${JOB_ID}.jsonl"
  
  log "  ├─ $span_name: ${span_status} (${span_duration_ms}ms)"
}

# Wrapper for timed span execution
time_span() {
  local span_name="$1"
  shift
  
  local start_time=$(date +%s%N)
  local output=""
  local exit_code=0
  
  # Execute command
  output=$("$@" 2>&1) || exit_code=$?
  
  local end_time=$(date +%s%N)
  local duration_ms=$(( (end_time - start_time) / 1000000 ))
  
  # Emit span with duration
  local status="OK"
  if [ $exit_code -ne 0 ]; then
    status="FAILED (exit=$exit_code)"
  fi
  
  emit_span "$span_name" "$status" "$duration_ms"
  
  [ $exit_code -eq 0 ] || return $exit_code
}

# Instrumentation for GitHub Actions workflow
instrument_workflow() {
  local workflow_file="$1"
  [ -f "$workflow_file" ] || error "Workflow file not found: $workflow_file"
  
  log "🔍 Instrumenting workflow: $workflow_file"
  
  # Extract job name, steps, etc.
  local job_count=$(yq '.jobs | length' "$workflow_file")
  
  # Add tracing sidecar to each job
  yq -i '.jobs |= map(
    .env.OTEL_EXPORTER_OTLP_ENDPOINT = "'$OTEL_COLLECTOR_ENDPOINT'" |
    .env.TRACE_SAMPLE_RATE = "'$TRACE_SAMPLE_RATE'" |
    .steps |= . + [{
      "name": "Setup OpenTelemetry",
      "run": "source /usr/local/bin/otel-init.sh"
    }]
  )' "$workflow_file"
  
  log "✓ Workflow instrumented: $job_count job(s) with tracing"
}

# Analyze traces for bottlenecks
analyze_traces() {
  local trace_file="${1:-./${JOB_ID}.jsonl}"
  
  [ -f "$trace_file" ] || error "Trace file not found: $trace_file"
  
  log "📈 Analyzing traces: $trace_file"
  
  # Extract slow spans (>1000ms)
  local slow_spans=$(jq -r '
    select(.resourceSpans[].scopeSpans[].spans[].endTimeUnixNano - 
            .resourceSpans[].scopeSpans[].spans[].startTimeUnixNano > 1000000000) |
    .resourceSpans[].scopeSpans[].spans[] |
    "\(.name): \((.endTimeUnixNano - .startTimeUnixNano) / 1000000 | floor)ms"
  ' "$trace_file" 2>/dev/null | sort -k2 -rn | head -10)
  
  echo "⚠️  Slow Spans (>1000ms):"
  echo "$slow_spans"
  
  # Calculate total execution time
  local total_duration=$(jq -r '
    .resourceSpans[].scopeSpans[].spans[] | 
    (.endTimeUnixNano - .startTimeUnixNano) / 1000000
  ' "$trace_file" 2>/dev/null | awk '{s+=$1} END {print s}')
  
  echo ""
  echo "📊 Trace Statistics:"
  echo "  Total Duration: ${total_duration:-0}ms"
  echo "  Span Count: $(jq '[.resourceSpans[].scopeSpans[].spans[]] | length' "$trace_file" 2>/dev/null || echo "0")"
}

# Generate flamegraph from traces
generate_flamegraph() {
  local trace_file="${1:-./${JOB_ID}.jsonl}"
  local output_file="${2:-./${JOB_ID}.html}"
  
  [ -f "$trace_file" ] || error "Trace file not found: $trace_file"
  
  log "🔥 Generating flamegraph: $output_file"
  
  # Convert OTLP JSON to flamegraph format (stack samples)
  # Format: func_a;func_b;func_c 10  (10 samples in this stack)
  
  local stack_counts=$(jq -r '
    .resourceSpans[].scopeSpans[].spans[] as $span |
    "\($span.name) (\(($span.endTimeUnixNano - $span.startTimeUnixNano) / 1000000 | floor)ms)"
  ' "$trace_file" 2>/dev/null | sort | uniq -c | awk '{print $2, $1}')
  
  # Generate simple HTML flamegraph
  cat > "$output_file" <<'EOF'
<!DOCTYPE html>
<html>
<head>
  <title>OpenTelemetry Flamegraph</title>
  <script src="https://cdn.jsdelivr.net/npm/d3@7"></script>
  <style>
    body { font-family: monospace; margin: 20px; }
    .flame-rect { stroke: 1px solid rgba(0,0,0,0.1); cursor: pointer; }
    .flame-text { pointer-events: none; font-size: 11px; }
  </style>
</head>
<body>
  <h1>OpenTelemetry Flamegraph</h1>
  <div id="chart"></div>
  <script>
    const data = [
EOF
  
  echo "$stack_counts" | while read stack duration; do
    echo "      { stack: \"$stack\", duration: $duration },"
  done >> "$output_file"
  
  cat >> "$output_file" <<'EOF'
    ];
    
    const svg = d3.select("#chart").append("svg").attr("width", 1000).attr("height", 400);
    data.forEach((d, i) => {
      svg.append("rect")
        .attr("class", "flame-rect")
        .attr("x", i * 30)
        .attr("y", 0)
        .attr("width", d.duration)
        .attr("height", 30)
        .attr("fill", `hsl(${Math.random() * 360}, 70%, 50%)`);
      
      svg.append("text")
        .attr("class", "flame-text")
        .attr("x", i * 30 + 5)
        .attr("y", 20)
        .text(d.stack.substring(0, 15));
    });
  </script>
</body>
</html>
EOF
  
  log "✓ Flamegraph generated: $output_file"
}

# Setup environment for tracing
setup_otel_env() {
  cat > /usr/local/bin/otel-init.sh <<'OTEL_INIT'
#!/bin/bash
# OpenTelemetry environment initialization

export OTEL_SDK_DISABLED=false
export OTEL_TRACES_EXPORTER=otlp
export OTEL_METRICS_EXPORTER=otlp
export OTEL_EXPORTER_OTLP_PROTOCOL="${OTEL_EXPORTER_OTLP_PROTOCOL:-grpc}"
export OTEL_EXPORTER_OTLP_ENDPOINT="${OTEL_COLLECTOR_ENDPOINT:-http://localhost:4317}"
export OTEL_PYTHON_LOGGING_AUTO_INSTRUMENTATION_ENABLED=true

# For subprocess tracing
export PYTHONPATH=/usr/local/lib/otel-packages:$PYTHONPATH
OTEL_INIT
  
  chmod +x /usr/local/bin/otel-init.sh
  log "✓ OpenTelemetry environment initialized"
}

# Main CLI
main() {
  case "${1:-help}" in
    init)
      init_trace_context "$2" "$3"
      ;;
    emit)
      emit_span "$2" "${3:-OK}" "${4:-0}"
      ;;
    time)
      shift
      time_span "$@"
      ;;
    instrument-workflow)
      instrument_workflow "$2"
      ;;
    analyze)
      analyze_traces "${2:-.}"
      ;;
    flamegraph)
      generate_flamegraph "${2:-.}" "${3:-.}"
      ;;
    setup)
      setup_otel_env
      ;;
    *)
      cat <<'HELP'
OpenTelemetry Tracer - Distributed Tracing for GitHub Actions

Usage:
  otel-tracer init <job_id> <repository>              Initialize trace context
  otel-tracer emit <span_name> [status] [duration_ms]  Emit a span
  otel-tracer time <span_name> <command...>           Time & trace a command
  otel-tracer instrument-workflow <workflow.yaml>      Add tracing to workflow
  otel-tracer analyze [trace_file]                     Analyze traces for bottlenecks
  otel-tracer flamegraph [input] [output.html]         Generate flamegraph visualization
  otel-tracer setup                                    Initialize environment

Examples:
  otel-tracer init job-123 my-org/my-repo
  otel-tracer emit "Build Docker Image" OK 15000
  otel-tracer time "Run Tests" pytest tests/
  otel-tracer analyze ./job-123.jsonl
  otel-tracer flamegraph ./job-123.jsonl ./flamegraph.html

Environment Variables:
  OTEL_COLLECTOR_ENDPOINT              OpenTelemetry Collector gRPC endpoint
  OTEL_EXPORTER_OTLP_PROTOCOL          Export protocol (grpc, http/protobuf)
  TRACE_SAMPLE_RATE                    Sampling rate (0.0-1.0)
  TRACE_LOG_DIR                        Local trace log directory

HELP
      exit 1
      ;;
  esac
}

main "$@"
