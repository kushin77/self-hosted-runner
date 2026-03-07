#!/usr/bin/env bash
# Universal resilience utilities for GitHub Actions workflows
# Provides: retry with exponential backoff, idempotency checks, safe API calls
# Usage: source .github/scripts/resilience.sh

set -o pipefail

# retry_command: Execute command with exponential backoff and jitter
# Usage: retry_command <MAX_RETRIES> <INITIAL_DELAY_SECONDS> <COMMAND...>
# Returns: Command exit code; fails if all retries exhausted
retry_command() {
  local max_retries=${1:?}
  local initial_delay=${2:?}
  shift 2
  local cmd=("$@")
  local attempt=1
  local delay=$initial_delay
  
  while [ $attempt -le $max_retries ]; do
    echo "[attempt $attempt/$max_retries] executing: ${cmd[*]}" >&2
    if "${cmd[@]}"; then
      echo "[success on attempt $attempt]" >&2
      return 0
    fi
    
    if [ $attempt -lt $max_retries ]; then
      # Calculate delay with jitter (±20%)
      local jitter=$((RANDOM % (delay / 5 + 1)))
      if [ $((RANDOM % 2)) -eq 0 ]; then
        delay=$((delay + jitter))
      else
        delay=$((delay - jitter))
      fi
      delay=$((delay < 1 ? 1 : delay))
      echo "[retry in ${delay}s] attempt $((attempt + 1)) of $max_retries" >&2
      sleep "$delay"
      delay=$((delay * 2))  # exponential backoff
      delay=$((delay > 600 ? 600 : delay))  # cap at 10 minutes
    fi
    
    attempt=$((attempt + 1))
  done
  
  echo "[FAILED after $max_retries attempts]" >&2
  return 1
}

# gh_safe: Execute gh command with retry, timeout, and error handling
# Usage: gh_safe <MAX_RETRIES> <TIMEOUT_SECONDS> <GH_COMMAND...>
# Returns: Command exit code; retries on transient errors
gh_safe() {
  local max_retries=${1:?}
  local timeout_secs=${2:?}
  shift 2
  local gh_cmd=("$@")
  
  # Wrap gh command with timeout
  local cmd=(timeout "$timeout_secs" gh "${gh_cmd[@]}")
  
  # Retry with backoff
  retry_command "$max_retries" 2 "${cmd[@]}"
}

# idempotent_issue_comment: Post comment to issue only if not already posted
# Usage: idempotent_issue_comment <ISSUE_NUM> <MARKER_TEXT> <COMMENT_BODY>
# Returns: 0 if comment posted or already exists; 1 on error
idempotent_issue_comment() {
  local issue_num=${1:?}
  local marker=${2:?}
  local body=${3:?}
  local repo=${4:-kushin77/self-hosted-runner}
  
  # Check if marker comment already exists
  if gh issue view "$issue_num" --repo "$repo" --json comments --jq ".comments[] | select(.body | contains(\"$marker\")) | .id" | grep -q .; then
    echo "[idempotent_issue_comment] marker '$marker' already exists on issue $issue_num" >&2
    return 0
  fi
  
  # Post new comment with marker
  echo "[idempotent_issue_comment] posting new comment to issue $issue_num" >&2
  gh issue comment "$issue_num" --repo "$repo" --body "$body" || return 1
  return 0
}

# poll_async_result: Poll a result (like a run status) with exponential backoff
# Usage: poll_async_result <MAX_POLLS> <INITIAL_DELAY> <CHECK_COMMAND> [<SUCCESS_CONDITION>]
# The CHECK_COMMAND should output the status; if it matches SUCCESS_CONDITION, polling stops
# Returns: 0 if condition met; 1 if max polls exceeded
poll_async_result() {
  local max_polls=${1:?}
  local initial_delay=${2:?}
  local check_cmd=${3:?}
  local success_cond=${4:-SUCCESS}
  local poll=1
  local delay=$initial_delay
  
  while [ $poll -le $max_polls ]; do
    echo "[poll $poll/$max_polls] checking result..." >&2
    local result
    result=$(eval "$check_cmd" || echo "ERROR")
    
    if [[ "$result" == *"$success_cond"* ]]; then
      echo "[poll_async_result] condition met: $result" >&2
      return 0
    fi
    
    if [ $poll -lt $max_polls ]; then
      # Jitter
      local jitter=$((RANDOM % (delay / 5 + 1)))
      delay=$((delay + jitter))
      echo "[poll_async_result] waiting ${delay}s before next poll..." >&2
      sleep "$delay"
      delay=$((delay * 2))
      delay=$((delay > 600 ? 600 : delay))
    fi
    
    poll=$((poll + 1))
  done
  
  echo "[poll_async_result] max polls ($max_polls) exceeded" >&2
  return 1
}

# idempotent_state_change: Execute a command that modifies state only if state not already changed
# Usage: idempotent_state_change <CHECK_COMMAND> <CHANGE_COMMAND> [<STATE_MARKER>]
# CHECK_COMMAND should return 0 if state change already applied
# Returns: 0 if already in desired state or successfully changed; 1 on failure
idempotent_state_change() {
  local check_cmd=${1:?}
  local change_cmd=${2:?}
  local marker=${3:-}
  
  echo "[idempotent_state_change] checking if state change needed..." >&2
  if eval "$check_cmd"; then
    echo "[idempotent_state_change] state already correct (marker: ${marker:-none})" >&2
    return 0
  fi
  
  echo "[idempotent_state_change] applying state change..." >&2
  if eval "$change_cmd"; then
    echo "[idempotent_state_change] state change successful" >&2
    return 0
  else
    echo "[idempotent_state_change] state change FAILED" >&2
    return 1
  fi
}

export -f retry_command
export -f gh_safe
export -f idempotent_issue_comment
export -f poll_async_result
export -f idempotent_state_change
