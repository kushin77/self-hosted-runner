#!/usr/bin/env bash
set -euo pipefail

# Safe runner: clone remediation branches, run frontend build/tests, merge passing PRs
# Requires: `node`, `npm`, and network access. To auto-merge, set env var GITHUB_TOKEN.

REPO="https://github.com/kushin77/self-hosted-runner.git"
GITHUB_API_REPO="kushin77/self-hosted-runner"
TMPROOT="$(mktemp -d -t remediation-tests.XXXX)"
EXIT_CODE=0

declare -a PRS=(
  "2252 remediation/frontend/vite-7.3.1"
  "2253 remediation/frontend/vitest-4.0.18"
  "2254 remediation/frontend/cypress-15.11.0"
  "2255 remediation/frontend/typescript-eslint-8.57.0"
)

echo "Running remediation tests in $TMPROOT"

for entry in "${PRS[@]}"; do
  PR_NUM="$(awk '{print $1}' <<<"$entry")"
  BRANCH="$(awk '{print $2}' <<<"$entry")"
  echo "--- Testing PR #${PR_NUM} (branch: ${BRANCH}) ---"

  TD="${TMPROOT}/pr-${PR_NUM}"
  if ! git clone --depth 1 --branch "$BRANCH" "$REPO" "$TD"; then
    echo "CLONE_FAIL for PR #${PR_NUM}"; EXIT_CODE=2; continue
  fi

  if [ ! -d "$TD/frontend" ]; then
    echo "NO_FRONTEND_DIR for PR #${PR_NUM}"; rm -rf "$TD"; EXIT_CODE=3; continue
  fi

  pushd "$TD/frontend" >/dev/null
  rm -rf node_modules package-lock.json || true

  if [ -f package-lock.json ]; then
    if ! npm ci --no-audit --no-fund; then
      echo "NPM_INSTALL_FAIL for PR #${PR_NUM}"; popd >/dev/null; rm -rf "$TD"; EXIT_CODE=4; continue
    fi
  else
    if ! npm install --no-audit --no-fund; then
      echo "NPM_INSTALL_FAIL (install) for PR #${PR_NUM}"; popd >/dev/null; rm -rf "$TD"; EXIT_CODE=4; continue
    fi
  fi

  if ! npm run build; then
    echo "BUILD_FAIL for PR #${PR_NUM}"; popd >/dev/null; rm -rf "$TD"; EXIT_CODE=5; continue
  fi

  if ! npm test -- --run; then
    echo "TEST_FAIL for PR #${PR_NUM}"; popd >/dev/null; rm -rf "$TD"; EXIT_CODE=6; continue
  fi

  echo "PR_PASS for #${PR_NUM}"

  if [ -n "${GITHUB_TOKEN:-}" ]; then
    echo "Attempting to merge PR #${PR_NUM} via GitHub API"
    code=$(curl -s -o /dev/null -w "%{http_code}" -X PUT \
      -H "Authorization: token ${GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/${GITHUB_API_REPO}/pulls/${PR_NUM}/merge" \
      -d "{\"commit_title\":\"chore: merge remediation PR #${PR_NUM}\",\"merge_method\":\"merge\"}")

    if [ "$code" = "200" ] || [ "$code" = "201" ]; then
      echo "MERGE_OK PR #${PR_NUM}"
    else
      echo "MERGE_FAILED_PR_${PR_NUM}: HTTP $code"
      EXIT_CODE=7
    fi
  else
    echo "GITHUB_TOKEN not set — skipping automated merge for PR #${PR_NUM}. Marking for manual merge."
  fi

  popd >/dev/null
  rm -rf "$TD"
done

echo "Done. Workspace: $TMPROOT (cleaned). Exit code: $EXIT_CODE"
exit $EXIT_CODE
