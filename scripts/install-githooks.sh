#!/usr/bin/env bash
# install-githooks.sh
# Auto-install git hooks by setting core.hooksPath to .githooks (no copy needed).
# Optionally publishes hooks to the distributed registry and pulls latest.
#
# IDEMPOTENT: safe to run multiple times — produces identical state.
# IMMUTABLE AUDIT: every operation logged to JSONL.
# NO GITHUB ACTIONS: direct git config + registry operations only.
#
# USAGE:
#   bash scripts/install-githooks.sh
#   bash scripts/install-githooks.sh --registry-update    # pull from registry first
#   bash scripts/install-githooks.sh --check-only         # verify, no changes
#
# CONSTRAINTS:
#   - No elevated privileges required
#   - Zero static credentials
#   - All operations audited (JSONL)

set -euo pipefail

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || cd "$(dirname "$0")/.." && pwd)"
HOOKS_SRC="${REPO_ROOT}/.githooks"
AUDIT_LOG="${REPO_ROOT}/logs/install-githooks-audit.jsonl"
REGISTRY_SCRIPT="${REPO_ROOT}/scripts/hook-registry/server.py"

CHECK_ONLY=false
REGISTRY_UPDATE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check-only)      CHECK_ONLY=true; shift ;;
    --registry-update) REGISTRY_UPDATE=true; shift ;;
    -h|--help)  grep '^#' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Colors & audit
# ---------------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
mkdir -p "$(dirname "$AUDIT_LOG")"
_audit() {
  printf '{"timestamp":"%s","event":"%s","details":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "${2:-}" >> "$AUDIT_LOG"
}
_ok()   { echo -e "${GREEN}  ✅ $*${NC}"; }
_warn() { echo -e "${YELLOW}  ⚠️  $*${NC}"; }
_fail() { echo -e "${RED}  ❌ $*${NC}"; }

echo -e "\n${YELLOW}→ Installing git hooks${NC}"

# ---------------------------------------------------------------------------
# Step 1: Verify source directory
# ---------------------------------------------------------------------------
if [[ ! -d "${HOOKS_SRC}" ]]; then
  _fail ".githooks directory not found at ${HOOKS_SRC}"
  exit 1
fi

# ---------------------------------------------------------------------------
# Step 2: Set core.hooksPath (idempotent)
# ---------------------------------------------------------------------------
CURRENT="$(git -C "${REPO_ROOT}" config core.hooksPath 2>/dev/null || true)"
if [[ "${CURRENT}" == ".githooks" ]]; then
  _ok "core.hooksPath already .githooks"
elif [[ "${CHECK_ONLY}" == "true" ]]; then
  _warn "core.hooksPath not set (check-only)"
else
  git -C "${REPO_ROOT}" config core.hooksPath .githooks
  _ok "core.hooksPath → .githooks"
  _audit "hooks_path_configured" ".githooks"
fi

# ---------------------------------------------------------------------------
# Step 3: Ensure hook files are executable
# ---------------------------------------------------------------------------
INSTALLED=0; FAIL=0
for hook_file in "${HOOKS_SRC}"/*; do
  [[ -f "${hook_file}" ]] || continue
  hook_name="$(basename "${hook_file}")"
  [[ "${hook_name}" == README* || "${hook_name}" == *.md ]] && continue
  if [[ "${CHECK_ONLY}" == "true" ]]; then
    [[ -x "${hook_file}" ]] && _ok "${hook_name} executable" || { _warn "${hook_name} not executable"; FAIL=$((FAIL+1)); }
  else
    chmod +x "${hook_file}"
    _ok "${hook_name}"
    _audit "hook_executable" "${hook_name}"
    INSTALLED=$((INSTALLED+1))
  fi
done

# ---------------------------------------------------------------------------
# Step 4: Optional registry pull
# ---------------------------------------------------------------------------
if [[ "${REGISTRY_UPDATE}" == "true" && -f "${REGISTRY_SCRIPT}" ]]; then
  echo -e "\n${YELLOW}→ Pulling from hook registry${NC}"
  python3 "${REGISTRY_SCRIPT}" update --hooks-dir "${HOOKS_SRC}" 2>/dev/null \
    && { _ok "Registry update complete"; _audit "registry_pull_complete" ""; } \
    || { _warn "Registry unavailable — using local hooks"; _audit "registry_pull_skipped" ""; }
fi

# ---------------------------------------------------------------------------
# Step 5: Auto-publish pre-push to registry (idempotent, version = sha prefix)
# ---------------------------------------------------------------------------
if [[ "${CHECK_ONLY}" == "false" && -f "${HOOKS_SRC}/pre-push" && -f "${REGISTRY_SCRIPT}" ]]; then
  HOOK_SHA="$(sha256sum "${HOOKS_SRC}/pre-push" 2>/dev/null | awk '{print substr($1,1,8)}' || true)"
  if [[ -n "${HOOK_SHA}" ]]; then
    VER="local-${HOOK_SHA}"
    python3 "${REGISTRY_SCRIPT}" publish \
      --hook pre-push --version "${VER}" \
      --file "${HOOKS_SRC}/pre-push" \
      --message "auto-published by install-githooks.sh" 2>/dev/null \
    && python3 "${REGISTRY_SCRIPT}" promote --hook pre-push --version "${VER}" 2>/dev/null \
    && { _ok "pre-push registered in hook registry as v${VER}"; _audit "hook_published" "pre-push version=${VER}"; } \
    || true  # non-fatal: registry may not be running
  fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
if [[ "${FAIL}" -eq 0 ]]; then
  [[ "${CHECK_ONLY}" == "true" ]] \
    && _ok "All hooks verified OK (check-only mode)" \
    || _ok "All hooks installed (${INSTALLED} hooks, core.hooksPath=.githooks)"
  _audit "install_complete" "installed=${INSTALLED} failures=0"
  exit 0
else
  _fail "${FAIL} hook(s) failed verification"
  _audit "install_failed" "failures=${FAIL}"
  exit 1
fi
