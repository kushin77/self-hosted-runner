#!/usr/bin/env bash
set -euo pipefail

# deploy-common.sh - shared deployment helper functions

deploy_upload_payload() {
  local compose_file="$1"
  local remote_user="$2"
  local remote_host="$3"
  local remote_dir="$4"

  local payload="/tmp/compose_payload.tgz"
  tar -C "$(dirname "$compose_file")" -czf "$payload" "$(basename "$compose_file")" || true
  scp "$payload" "${remote_user}@${remote_host}:/tmp/" || true
  rm -f "$payload" || true
}

deploy_execute_remote() {
  local compose_file="$1"
  local remote_user="$2"
  local remote_host="$3"
  local remote_dir="$4"
  local no_build="$5"

  ssh "${remote_user}@${remote_host}" bash -s <<'EOF'
set -euo pipefail
cd ${remote_dir}
tar xzf /tmp/compose_payload.tgz -C . || true
rm -f /tmp/compose_payload.tgz || true
if [ "${no_build}" -eq 0 ]; then
  docker-compose -f ${compose_file} pull || true
  docker-compose -f ${compose_file} up -d --build --remove-orphans || true
else
  docker-compose -f ${compose_file} pull || true
  docker-compose -f ${compose_file} up -d --remove-orphans || true
fi
sleep 5
docker-compose -f ${compose_file} ps || true
EOF
}

deploy_audit() {
  local audit_file="$1"
  local status="$2"
  local message="$3"
  mkdir -p "$(dirname "$audit_file")"
  printf '{"timestamp":"%s","status":"%s","message":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$status" "$message" >> "$audit_file"
}

return 0
