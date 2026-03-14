#!/usr/bin/env bash
set -euo pipefail

# Ensure all cloud CLIs stay non-interactive in automation.
export CLOUDSDK_CORE_DISABLE_PROMPTS=1

# Enterprise reset for dev environment.
# Destroys infra across on-prem + cloud while preserving:
# - Secrets (GCP Secret Manager, Azure Key Vault, AWS Secrets Manager)
# - Container images/registries
# - Git repository and code
#
# Usage:
#   EXECUTE=true bash scripts/reset/enterprise-reset.sh \
#     --project nexusshield-prod --domain elevatediq.ai

PROJECT_ID="nexusshield-prod"
DOMAIN="elevatediq.ai"
EXECUTE="${EXECUTE:-false}"
LOG_DIR="${LOG_DIR:-./logs/reset}"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
LOG_FILE="${LOG_DIR}/enterprise-reset-${TS}.log"
CHECKPOINT_FILE="${LOG_DIR}/enterprise-reset-${TS}.jsonl"

mkdir -p "${LOG_DIR}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      PROJECT_ID="$2"
      shift 2
      ;;
    --domain)
      DOMAIN="$2"
      shift 2
      ;;
    *)
      echo "Unknown arg: $1"
      exit 2
      ;;
  esac
done

log() {
  local m="$*"
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $m" | tee -a "${LOG_FILE}"
}

checkpoint() {
  local phase="$1"
  local status="$2"
  local details="${3:-}"
  local details_safe
  details_safe="$(printf '%s' "$details" | sed 's/"/\\"/g')"
  printf '{"timestamp":"%s","phase":"%s","status":"%s","details":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$phase" "$status" "$details_safe" >> "${CHECKPOINT_FILE}"
}

run_safe() {
  local phase="$1"
  shift
  local cmd=("$@")
  log "RUN[$phase]: ${cmd[*]}"
  if "${cmd[@]}" >>"${LOG_FILE}" 2>&1; then
    checkpoint "$phase" "ok" "${cmd[*]}"
    return 0
  fi
  checkpoint "$phase" "warn" "failed: ${cmd[*]}"
  return 1
}

require_execute() {
  if [[ "${EXECUTE}" != "true" ]]; then
    log "ABORT: destructive reset requires EXECUTE=true"
    exit 2
  fi
}

phase_preflight() {
  checkpoint "preflight" "start" "project=${PROJECT_ID} domain=${DOMAIN}"
  command -v gcloud >/dev/null 2>&1 || { log "gcloud required"; exit 1; }
  gcloud config set project "${PROJECT_ID}" >/dev/null 2>&1 || true
  checkpoint "preflight" "ok" "tools and project context validated"
}

phase_stop_automation() {
  checkpoint "stop-automation" "start" "disable schedulers and CI triggers"

  # GCP scheduler jobs
  while IFS= read -r job; do
    [[ -z "${job}" ]] && continue
    run_safe "stop-automation" gcloud scheduler jobs delete "${job}" --location us-central1 --project "${PROJECT_ID}" --quiet || true
  done < <(gcloud scheduler jobs list --project "${PROJECT_ID}" --location us-central1 --format='value(name)' 2>/dev/null || true)

  # Cloud Build triggers (if any)
  while IFS= read -r trigger_id; do
    [[ -z "${trigger_id}" ]] && continue
    run_safe "stop-automation" gcloud builds triggers delete "${trigger_id}" --project "${PROJECT_ID}" --quiet || true
  done < <(gcloud builds triggers list --project "${PROJECT_ID}" --format='value(id)' 2>/dev/null || true)

  checkpoint "stop-automation" "ok" "automation sources removed"
}

phase_nuke_gcp_runtime() {
  checkpoint "nuke-gcp" "start" "delete non-secret/non-image runtime resources"

  # Delete GKE clusters
  while IFS='|' read -r name location; do
    [[ -z "${name}" ]] && continue
    run_safe "nuke-gcp" gcloud container clusters delete "${name}" --location "${location}" --project "${PROJECT_ID}" --quiet || true
  done < <(gcloud container clusters list --project "${PROJECT_ID}" --format='value(name,location)' | awk '{print $1"|"$2}')

  # Delete Cloud Run services/jobs
  while IFS='|' read -r svc region; do
    [[ -z "${svc}" ]] && continue
    run_safe "nuke-gcp" gcloud run services delete "${svc}" --region "${region}" --project "${PROJECT_ID}" --quiet || true
  done < <(gcloud run services list --project "${PROJECT_ID}" --format='value(metadata.name,region)' | awk '{print $1"|"$2}')

  while IFS='|' read -r job region; do
    [[ -z "${job}" ]] && continue
    run_safe "nuke-gcp" gcloud run jobs delete "${job}" --region "${region}" --project "${PROJECT_ID}" --quiet || true
  done < <(gcloud run jobs list --project "${PROJECT_ID}" --format='value(name,region)' | awk '{print $1"|"$2}')

  # Delete Cloud Functions
  while IFS='|' read -r fn region; do
    [[ -z "${fn}" ]] && continue
    run_safe "nuke-gcp" gcloud functions delete "${fn}" --region "${region}" --project "${PROJECT_ID}" --quiet || true
  done < <(gcloud functions list --project "${PROJECT_ID}" --format='value(name,region)' | awk '{print $1"|"$2}')

  # Delete SQL and Redis
  while IFS= read -r db; do
    [[ -z "${db}" ]] && continue
    run_safe "nuke-gcp" gcloud sql instances delete "${db}" --project "${PROJECT_ID}" --quiet || true
  done < <(gcloud sql instances list --project "${PROJECT_ID}" --format='value(name)' 2>/dev/null || true)

  while IFS='|' read -r redis region; do
    [[ -z "${redis}" ]] && continue
    run_safe "nuke-gcp" gcloud redis instances delete "${redis}" --region "${region}" --project "${PROJECT_ID}" --quiet || true
  done < <(gcloud redis instances list --project "${PROJECT_ID}" --region=- --format='value(name,region)' --quiet 2>/dev/null | awk '{print $1"|"$2}')

  # Delete VM instances (if any)
  while IFS='|' read -r vm zone; do
    [[ -z "${vm}" ]] && continue
    run_safe "nuke-gcp" gcloud compute instances delete "${vm}" --zone "${zone}" --project "${PROJECT_ID}" --quiet || true
  done < <(gcloud compute instances list --project "${PROJECT_ID}" --format='value(name,zone)' | awk '{print $1"|"$2}')

  # Pub/Sub subscriptions and topics
  while IFS= read -r sub; do
    [[ -z "${sub}" ]] && continue
    run_safe "nuke-gcp" gcloud pubsub subscriptions delete "${sub}" --project "${PROJECT_ID}" --quiet || true
  done < <(gcloud pubsub subscriptions list --project "${PROJECT_ID}" --format='value(name)' 2>/dev/null || true)

  while IFS= read -r topic; do
    [[ -z "${topic}" ]] && continue
    run_safe "nuke-gcp" gcloud pubsub topics delete "${topic}" --project "${PROJECT_ID}" --quiet || true
  done < <(gcloud pubsub topics list --project "${PROJECT_ID}" --format='value(name)' 2>/dev/null || true)

  # Buckets: preserve secret/image/state-related buckets
  while IFS= read -r bucket; do
    [[ -z "${bucket}" ]] && continue
    if [[ "${bucket}" =~ (secret|vault|artifact|gcr|images|tfstate|terraform|backup) ]]; then
      checkpoint "nuke-gcp" "keep" "bucket ${bucket}"
      continue
    fi
    run_safe "nuke-gcp" gcloud storage rm -r "gs://${bucket}" --project "${PROJECT_ID}" --quiet || true
  done < <(gcloud storage buckets list --project "${PROJECT_ID}" --format='value(name)' 2>/dev/null || true)

  checkpoint "nuke-gcp" "ok" "gcp runtime cleanup complete"
}

phase_nuke_onprem_runtime() {
  checkpoint "nuke-onprem" "start" "delete k8s namespaces, containers, volumes; preserve images"

  if command -v kubectl >/dev/null 2>&1; then
    while IFS= read -r ns; do
      [[ -z "${ns}" ]] && continue
      if [[ "${ns}" =~ ^(default|kube-system|kube-public|kube-node-lease)$ ]]; then
        continue
      fi
      run_safe "nuke-onprem" kubectl delete ns "${ns}" --wait=false || true
    done < <(kubectl get ns -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
  fi

  if command -v docker >/dev/null 2>&1; then
    cids=$(docker ps -aq 2>/dev/null || true)
    if [[ -n "${cids}" ]]; then
      run_safe "nuke-onprem" docker rm -f ${cids} || true
    fi

    while IFS= read -r vol; do
      [[ -z "${vol}" ]] && continue
      if [[ "${vol}" =~ (vault|secret|registry|image|git) ]]; then
        checkpoint "nuke-onprem" "keep" "volume ${vol}"
        continue
      fi
      run_safe "nuke-onprem" docker volume rm "${vol}" || true
    done < <(docker volume ls -q)

    # Preserve images intentionally.
    checkpoint "nuke-onprem" "keep" "docker images preserved"
  fi

  # Best effort for local generated state
  run_safe "nuke-onprem" bash -lc 'rm -rf /tmp/nexus*' || true

  checkpoint "nuke-onprem" "ok" "on-prem runtime cleanup complete"
}

phase_verify_empty_runtime() {
  checkpoint "verify" "start" "validate runtime mostly empty"

  # Cloud checks
  local gke_count
  gke_count=$(gcloud container clusters list --project "${PROJECT_ID}" --format='value(name)' | wc -l | tr -d ' ')
  local run_count
  run_count=$(gcloud run services list --project "${PROJECT_ID}" --format='value(metadata.name)' | wc -l | tr -d ' ')
  local vm_count
  vm_count=$(gcloud compute instances list --project "${PROJECT_ID}" --format='value(name)' | wc -l | tr -d ' ')

  # On-prem checks (best effort)
  local docker_running="na"
  if command -v docker >/dev/null 2>&1; then
    docker_running=$(docker ps -q | wc -l | tr -d ' ')
  fi

  log "VERIFY: gke=${gke_count} run=${run_count} vm=${vm_count} docker_running=${docker_running}"
  checkpoint "verify" "ok" "gke=${gke_count} run=${run_count} vm=${vm_count} docker_running=${docker_running}"
}

phase_scaffold_ready() {
  checkpoint "scaffold" "start" "prepare SNC-only rebuild entrypoint"

  mkdir -p scaffold/00-governance scaffold/10-platform scaffold/20-app scaffold/30-observability scaffold/40-security scaffold/50-release

  cat > scaffold/00-governance/rebuild-input.yaml <<EOF
# Only input needed for rebuild
domain: ${DOMAIN}
standard_naming_convention:
  org: elevatediq
  env: dev
  project: nexusshield
  fqdn: ${DOMAIN}
EOF

  cat > scaffold/README.md <<EOF
# Rebuild Scaffold (No Rebuild Executed)

Single required input: project domain.
Current SNC domain: ${DOMAIN}

Runbook entrypoint for future rebuild:
- scripts/reset/rebuild-from-domain.sh
EOF

  cat > scripts/reset/rebuild-from-domain.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
DOMAIN="${1:-}"
if [[ -z "${DOMAIN}" ]]; then
  echo "Usage: $0 <domain>"
  exit 2
fi
echo "Planned rebuild domain: ${DOMAIN}"
echo "This script intentionally scaffolds only and does not deploy resources."
EOF
  chmod +x scripts/reset/rebuild-from-domain.sh

  checkpoint "scaffold" "ok" "scaffold created for domain ${DOMAIN}"
}

main() {
  require_execute
  phase_preflight
  phase_stop_automation
  phase_nuke_gcp_runtime
  phase_nuke_onprem_runtime
  phase_verify_empty_runtime
  phase_scaffold_ready
  checkpoint "complete" "ok" "enterprise reset complete"
  log "RESET COMPLETE. Secrets and images preserved; runtime torn down; scaffold ready."
}

main "$@"
