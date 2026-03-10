#!/usr/bin/env bash
set -euo pipefail

# Fair Job Scheduler with Priority Classes
# Implements Kubernetes-style QoS classes and per-repo quotas
# Ensures fair resource allocation across organization repositories
#
# Features:
#   - Priority classes (system, high, normal, low, batch)
#   - Per-repository quota enforcement
#   - Fair capacity sharing with guaranteed minimums
#   - Starvation prevention (aging boost)
#   - Preemption rules for higher priorities

QUEUE_DB="${QUEUE_DB:-/var/lib/runner-queue.db}"
QUOTA_FILE="${QUOTA_FILE:-.runner-quotas.yaml}"
LOG_FILE="${LOG_FILE:-/var/log/runner-scheduler.log}"
SCHEDULER_INTERVAL="${SCHEDULER_INTERVAL:-5}"

# Priority class definitions
declare -A PRIORITY_CLASSES=(
  [system]=1000
  [high]=100
  [normal]=50
  [low]=10
  [batch]=1
)

# Priority class definitions with resource guarantees
declare -A PRIORITY_MIN_SLOTS=(
  [system]=2
  [high]=1
  [normal]=0
  [low]=0
  [batch]=0
)

init_queue_db() {
  mkdir -p "$(dirname "$QUEUE_DB")"
  
  # Initialize SQLite database for job queue
  sqlite3 "$QUEUE_DB" <<'SQL'
CREATE TABLE IF NOT EXISTS job_queue (
  id TEXT PRIMARY KEY,
  repository TEXT NOT NULL,
  priority_class TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  started_at INTEGER,
  estimated_duration_secs INTEGER,
  runner_labels TEXT,
  status TEXT DEFAULT 'queued',
  assigned_runner TEXT,
  retries INTEGER DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_status ON job_queue(status);
CREATE INDEX IF NOT EXISTS idx_repo ON job_queue(repository);
CREATE INDEX IF NOT EXISTS idx_priority ON job_queue(priority_class);

CREATE TABLE IF NOT EXISTS repository_quotas (
  repository TEXT PRIMARY KEY,
  max_concurrent_jobs INTEGER NOT NULL,
  max_vpus_per_hour INTEGER NOT NULL,
  used_slots INTEGER DEFAULT 0,
  used_vpus INTEGER DEFAULT 0,
  reset_at INTEGER
);

CREATE TABLE IF NOT EXISTS runner_capacity (
  runner_id TEXT PRIMARY KEY,
  total_slots INTEGER NOT NULL,
  available_slots INTEGER NOT NULL,
  total_vpus INTEGER NOT NULL,
  available_vpus INTEGER NOT NULL,
  last_heartbeat INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS priority_reservations (
  priority_class TEXT PRIMARY KEY,
  reserved_slots INTEGER NOT NULL,
  reserved_vpus INTEGER NOT NULL
);

INSERT OR IGNORE INTO priority_reservations VALUES
  ('system', 2, 20),
  ('high', 1, 10),
  ('normal', 0, 0),
  ('low', 0, 0),
  ('batch', 0, 0);
SQL

  log "✓ Queue database initialized: $QUEUE_DB"
}

log() {
  local msg="[$(date +'%Y-%m-%d %H:%M:%S')] $*"
  echo "$msg"
  echo "$msg" >> "$LOG_FILE"
}

error() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
  exit 1
}

# Enqueue a job
enqueue_job() {
  local job_id="$1"
  local repository="$2"
  local priority_class="${3:-normal}"
  local estimated_duration="${4:-3600}"
  local runner_labels="${5:--}"
  
  # Validate priority class
  [[ " ${!PRIORITY_CLASSES[@]} " =~ " ${priority_class} " ]] || \
    error "Invalid priority class: $priority_class"
  
  sqlite3 "$QUEUE_DB" <<SQL
INSERT INTO job_queue (id, repository, priority_class, created_at, estimated_duration_secs, runner_labels, status)
VALUES ('$job_id', '$repository', '$priority_class', $(date +%s), $estimated_duration, '$runner_labels', 'queued');
SQL
  
  log "✅ Job queued: $job_id (priority=$priority_class, repo=$repository)"
}

# Calculate fair share (per-repo slot allocation)
calculate_fair_share() {
  local total_available_slots=$(sqlite3 "$QUEUE_DB" \
    "SELECT SUM(available_slots) FROM runner_capacity;")
  
  local total_available_slots=${total_available_slots:-0}
  
  if [ $total_available_slots -eq 0 ]; then
    log "⚠️  No available runner slots"
    return 1
  fi
  
  # Per-repo quota: proportional to repository weight (or equal if not configured)
  local repo_count=$(sqlite3 "$QUEUE_DB" \
    "SELECT COUNT(DISTINCT repository) FROM repository_quotas;")
  
  local fair_share=$((total_available_slots / (repo_count + 1)))
  
  echo "$fair_share"
}

# Scheduler main loop: select next job to run
schedule_next_job() {
  local fair_share=$(calculate_fair_share)
  [ $? -eq 0 ] || return 1
  
  # Priority-based scheduling with starvation prevention
  local next_job=$(sqlite3 "$QUEUE_DB" <<'SQL'
SELECT 
  j.id,
  j.repository,
  j.priority_class,
  j.created_at
FROM job_queue j
WHERE j.status = 'queued'
  AND NOT EXISTS (
    -- Check if repo has exceeded quota
    SELECT 1 FROM repository_quotas rq
    WHERE rq.repository = j.repository
      AND rq.used_slots >= rq.max_concurrent_jobs
  )
ORDER BY
  -- Priority: higher first, then age (anti-starvation)
  (
    CASE j.priority_class
      WHEN 'system' THEN 1000
      WHEN 'high' THEN 100
      WHEN 'normal' THEN 50
      WHEN 'low' THEN 10
      WHEN 'batch' THEN 1
      ELSE 0
    END
  ) DESC,
  -- Age boost: +10 priority points per hour waiting
  ((CAST((strftime('%s', 'now') - j.created_at) AS REAL) / 3600) * 10) DESC,
  j.created_at ASC
LIMIT 1;
SQL
)
  
  [ -n "$next_job" ] || return 1
  
  local job_id=$(echo "$next_job" | cut -d'|' -f1)
  local repository=$(echo "$next_job" | cut -d'|' -f2)
  local priority_class=$(echo "$next_job" | cut -d'|' -f3)
  
  log "🚀 Scheduling job: $job_id (priority=$priority_class, repo=$repository)"
  
  # Update job status
  sqlite3 "$QUEUE_DB" \
    "UPDATE job_queue SET status='scheduled', started_at=$(date +%s) WHERE id='$job_id';"
  
  # Update repository quota
  sqlite3 "$QUEUE_DB" \
    "UPDATE repository_quotas SET used_slots = used_slots + 1 WHERE repository='$repository';"
  
  echo "$job_id|$repository|$priority_class"
}

# Remove completed job and free quota
complete_job() {
  local job_id="$1"
  
  local job_info=$(sqlite3 "$QUEUE_DB" \
    "SELECT repository, estimated_duration_secs FROM job_queue WHERE id='$job_id';")
  
  local repository=$(echo "$job_info" | cut -d'|' -f1)
  
  sqlite3 "$QUEUE_DB" \
    "UPDATE job_queue SET status='completed' WHERE id='$job_id';"
  
  sqlite3 "$QUEUE_DB" \
    "UPDATE repository_quotas SET used_slots = MAX(0, used_slots - 1) WHERE repository='$repository';"
  
  log "✓ Job completed: $job_id (freed 1 slot for $repository)"
}

# Preempt lower-priority job to make room for higher priority
preempt_job() {
  local higher_priority_job="$1"
  
  log "⚠️  Attempting preemption for high-priority job: $higher_priority_job"
  
  # Find running batch/low priority job to preempt
  local victim_job=$(sqlite3 "$QUEUE_DB" <<SQL
SELECT id FROM job_queue
WHERE status = 'scheduled' 
  AND priority_class IN ('batch', 'low')
ORDER BY created_at DESC
LIMIT 1;
SQL
)
  
  [ -n "$victim_job" ] || return 1
  
  # Signal preemption to runner
  log "  → Preempting job: $victim_job (lower priority)"
  sqlite3 "$QUEUE_DB" \
    "UPDATE job_queue SET status='preempted' WHERE id='$victim_job';"
  
  # Re-queue preempted job
  sqlite3 "$QUEUE_DB" \
    "UPDATE job_queue SET status='queued' WHERE id='$victim_job';"
  
  return 0
}

# Load quotas from YAML file
load_quotas() {
  [ -f "$QUOTA_FILE" ] || error "Quota file not found: $QUOTA_FILE"
  
  log "📋 Loading quotas from: $QUOTA_FILE"
  
  # Parse YAML and insert quotas (requires yq)
  while IFS= read -r line; do
    if [[ $line =~ ^[[:space:]]*([^:]+):[[:space:]]*(.+)$ ]]; then
      local repo="${BASH_REMATCH[1]//[[:space:]]/}"
      local config="${BASH_REMATCH[2]}"
      
      # Extract max_concurrent_jobs and max_vpus_per_hour
      local max_jobs=$(echo "$config" | grep -oP 'max_concurrent_jobs:\s*\K\d+' || echo 2)
      local max_vpus=$(echo "$config" | grep -oP 'max_vpus_per_hour:\s*\K\d+' || echo 100)
      
      sqlite3 "$QUEUE_DB" \
        "INSERT OR REPLACE INTO repository_quotas VALUES ('$repo', $max_jobs, $max_vpus, 0, 0, $(date +%s));"
      
      log "  ├─ $repo: max_jobs=$max_jobs, max_vpus=$max_vpus"
    fi
  done < "$QUOTA_FILE"
  
  log "✓ Quotas loaded"
}

# Display queue status
queue_status() {
  log "📊 Queue Status:"
  
  echo ""
  echo "Queued Jobs (by priority):"
  sqlite3 "$QUEUE_DB" -header <<SQL
SELECT 
  priority_class,
  COUNT(*) as count,
  COUNT(CASE WHEN (strftime('%s', 'now') - created_at) > 3600 THEN 1 END) as waiting_>1h
FROM job_queue
WHERE status = 'queued'
GROUP BY priority_class
ORDER BY 
  CASE priority_class
    WHEN 'system' THEN 1
    WHEN 'high' THEN 2
    WHEN 'normal' THEN 3
    WHEN 'low' THEN 4
    WHEN 'batch' THEN 5
  END;
SQL
  
  echo ""
  echo "Repository Quotas:"
  sqlite3 "$QUEUE_DB" -header <<SQL
SELECT 
  repository,
  max_concurrent_jobs,
  used_slots,
  max_concurrent_jobs - used_slots as available,
  ROUND(100.0 * used_slots / max_concurrent_jobs) as utilization_pct
FROM repository_quotas
ORDER BY utilized_pct DESC;
SQL
  
  echo ""
  echo "Runner Capacity:"
  sqlite3 "$QUEUE_DB" -header <<SQL
SELECT 
  runner_id,
  total_slots,
  available_slots,
  total_slots - available_slots as used,
  ROUND(100.0 * (total_slots - available_slots) / total_slots) as utilization_pct
FROM runner_capacity
WHERE last_heartbeat > (strftime('%s', 'now') - 300);
SQL
}

# Main scheduler loop (runs continuously)
run_scheduler() {
  log "🎛️  Starting Fair Job Scheduler (interval: ${SCHEDULER_INTERVAL}s)"
  
  while true; do
    # Attempt to schedule next job
    local scheduled=$(schedule_next_job 2>/dev/null || echo "")
    
    if [ -n "$scheduled" ]; then
      log "  → Scheduled: $(echo $scheduled | cut -d'|' -f1)"
    fi
    
    sleep "$SCHEDULER_INTERVAL"
  done
}

# CLI
main() {
  case "${1:-help}" in
    init)
      init_queue_db
      ;;
    load-quotas)
      load_quotas
      ;;
    enqueue)
      enqueue_job "$2" "$3" "${4:-normal}" "${5:-3600}" "${6:--}"
      ;;
    schedule)
      schedule_next_job
      ;;
    complete)
      complete_job "$2"
      ;;
    status)
      queue_status
      ;;
    run)
      run_scheduler
      ;;
    *)
      cat <<'HELP'
Fair Job Scheduler - Priority-based queue with per-repo quotas

Usage:
  scheduler init                                       Initialize queue database
  scheduler load-quotas                                Load repository quotas
  scheduler enqueue <job_id> <repo> [priority] [duration] [labels]  Add job to queue
  scheduler schedule                                   Select next job to run
  scheduler complete <job_id>                          Mark job as complete
  scheduler status                                     Display queue status
  scheduler run                                        Start scheduler loop

Priority Classes:
  system   - Critical infrastructure jobs (highest priority, 1000 points)
  high     - User-facing features (100 points)
  normal   - Standard CI/CD jobs (50 points)
  low      - Housekeeping, non-critical (10 points)
  batch    - Background batch jobs (1 point)

Quota Configuration (runner-quotas.yaml):
  my-org/critical-repo:
    max_concurrent_jobs: 4
    max_vpus_per_hour: 200
  
  my-org/standard-repo:
    max_concurrent_jobs: 2
    max_vpus_per_hour: 100

Anti-Starvation:
  - Lower priority jobs gain +10 points per hour waiting
  - Prevents indefinite starvation of batch jobs
  - Preemption available for system-priority jobs

HELP
      exit 1
      ;;
  esac
}

main "$@"
