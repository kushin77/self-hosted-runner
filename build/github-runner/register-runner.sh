#!/usr/bin/env bash
set -euo pipefail

# Idempotent runner registration helper
# Usage:
#  - With gh installed and authenticated: script auto-generates the registration token
#  - Or provide RUNNER_TOKEN env var or pass token interactively

GITHUB_REPO="${GITHUB_REPO:-kushin77/ElevatedIQ-Mono-Repo}"
GITHUB_URL="${GITHUB_URL:-https://github.com/${GITHUB_REPO}}"
COMPOSE_FILE="docker-compose.yml"
WORK_DIR="/home/akushnir/ElevatedIQ-Mono-Mono-Repo/build/github-runner"
CONTAINER_NAME="elevatediq-github-runner"

echo "Register-runner helper"
echo "Repo: $GITHUB_REPO"
echo "URL: $GITHUB_URL"

cd "$WORK_DIR"

acquire_token()
{
  if command -v gh >/dev/null 2>&1; then
    if gh auth status >/dev/null 2>&1; then
      echo "Generating registration token via gh..."
      REG_TOKEN=$(gh api repos/${GITHUB_REPO}/actions/runners/registration-token -X POST -q .token 2>/dev/null || true)
      if [ -n "${REG_TOKEN:-}" ]; then
        echo "Got token from gh"
        echo "$REG_TOKEN"
        return 0
      fi
    else
      echo "gh found but not authenticated. Skipping automatic token retrieval."
    fi
  fi

  if [ -n "${RUNNER_TOKEN:-}" ]; then
    echo "Using RUNNER_TOKEN from environment"
    echo "$RUNNER_TOKEN"
    return 0
  fi

  echo "No automatic token available. Please paste a repository registration token (from $GITHUB_URL/settings/actions/runners/new):"
  read -r -p "Registration token: " INPUT_TOKEN
  if [ -z "$INPUT_TOKEN" ]; then
    echo "No token provided; aborting." >&2
    return 1
  fi
  echo "$INPUT_TOKEN"
  return 0
}

main()
{
  # Acquire a token (or fail)
  TOKEN=$(acquire_token) || { echo "Failed to acquire runner registration token"; exit 2; }

  export RUNNER_TOKEN="$TOKEN"
  export GITHUB_URL

  echo "Bringing up runner container via docker-compose..."
  # Ensure compose file exists
  if [ ! -f "$COMPOSE_FILE" ]; then
    echo "Compose file not found: $COMPOSE_FILE" >&2
    exit 3
  fi

  # Start the container
  docker-compose -f "$COMPOSE_FILE" up -d --remove-orphans

  echo "Waiting for container to start..."
  sleep 3

  # Wait for registration / listener
  echo "Tailing logs; will wait up to 2 minutes for registration/listening message"
  SECONDS_WAITED=0
  MAX_WAIT=120
  while [ $SECONDS_WAITED -lt $MAX_WAIT ]; do
    docker ps --filter name="$CONTAINER_NAME" --format "{{.Names}} {{.Status}}" | grep -q "$CONTAINER_NAME" || true
    docker logs "$CONTAINER_NAME" --tail 200 2>/dev/null | sed -n '1,200p'
    if docker logs "$CONTAINER_NAME" --tail 200 2>/dev/null | grep -i -E "listening for jobs|listening for work|listening on|runner listener" >/dev/null 2>&1; then
      echo "Runner appears to be listening for jobs."
      return 0
    fi
    if docker logs "$CONTAINER_NAME" --tail 50 2>/dev/null | grep -i "Not Found\|404" >/dev/null 2>&1; then
      echo "Registration returned Not Found (404) — token may be invalid or wrong scope" >&2
      return 4
    fi
    sleep 5
    SECONDS_WAITED=$((SECONDS_WAITED+5))
  done

  echo "Timed out waiting for runner to start; check logs at: docker logs $CONTAINER_NAME" >&2
  return 5
}

main "$@"
