#!/usr/bin/env bash
set -euo pipefail

# run-purge-and-scan.sh
# Helper to run the history purge and a gitleaks scan from a workstation/CI
# Usage (recommended):
#   FORCE=1 ./run-purge-and-scan.sh --repo git@github.com:kushin77/self-hosted-runner.git

usage(){
  cat <<EOF
Usage: FORCE=1 $0 --repo <mirror-ssh-url> [--outdir ./out]

This script will:
 - create a mirror clone and a backup bundle
 - setup a Python venv and install git-filter-repo
 - run git-filter-repo to remove known sensitive paths
 - run gitleaks to produce /tmp/secret-scan-report.json (or in outdir)
 - if FORCE=1, push cleaned history to origin (force)

You MUST run this from a trusted workstation with git SSH write access.
EOF
  exit 1
}

REPO_URL=""
OUTDIR="$(pwd)/purge-output-$(date +%Y%m%d%H%M%S)"

while [[ $# -gt 0 ]]; do
  case $1 in
    --repo) REPO_URL="$2"; shift 2;;
    --outdir) OUTDIR="$2"; shift 2;;
    -h|--help) usage;;
    *) echo "Unknown arg: $1"; usage;;
  esac
done

if [ -z "$REPO_URL" ]; then
  echo "Error: --repo is required" >&2
  usage
fi

mkdir -p "$OUTDIR"
TMPDIR=$(mktemp -d)
MIRROR="$TMPDIR/repo.git"
BACKUP="$OUTDIR/backup.bundle"
GITLEAKS_REPORT="$OUTDIR/secret-scan-report.json"

echo "Mirror cloning $REPO_URL -> $MIRROR"
git clone --mirror "$REPO_URL" "$MIRROR"
cd "$MIRROR"

echo "Creating backup bundle: $BACKUP"
git bundle create "$BACKUP" --all

# Setup a venv and install git-filter-repo
VENV="$OUTDIR/venv"
python3 -m venv "$VENV"
. "$VENV/bin/activate"
python -m pip install --upgrade pip
python -m pip install git-filter-repo

echo "Running git-filter-repo (dry-run first)"

# Run a non-destructive dry-run by copying mirror, then filter
DRY="$TMPDIR/dry.git"
git clone --mirror "$REPO_URL" "$DRY"
cd "$DRY"

. "$VENV/bin/activate"
# Remove sensitive paths
. "$VENV/bin/git-filter-repo" --invert-paths \
  --paths .runner-keys/self-hosted-runner.ed25519 \
  --paths .runner-keys/self-hosted-runner.ed25519.pub \
  --paths build/test_signing_key.pem \
  --paths build/test_ssh_key

# Run gitleaks against the cleaned repo (optional)
cd "$DRY"
if ! command -v gitleaks >/dev/null 2>&1; then
  echo "gitleaks not found in PATH. Attempting install via pip in venv."
  python -m pip install gitleaks
fi

echo "Running gitleaks (this may take a while)"
set +e
gitleaks detect --source . --report-format json --report-path "$GITLEAKS_REPORT" --no-banner
GL_EXIT=$?
set -e

if [ -f "$GITLEAKS_REPORT" ]; then
  echo "Gitleaks report saved to: $GITLEAKS_REPORT"
else
  echo "Gitleaks did not produce a report at $GITLEAKS_REPORT" >&2
fi

if [ "${FORCE:-0}" != "1" ]; then
  echo "FORCE not set. Exiting without pushing. Review $BACKUP and $GITLEAKS_REPORT in $OUTDIR"
  exit 0
fi

# If FORCE=1, perform actual filter & push
cd "$MIRROR"
. "$VENV/bin/activate"
. "$VENV/bin/git-filter-repo" --invert-paths \
  --paths .runner-keys/self-hosted-runner.ed25519 \
  --paths .runner-keys/self-hosted-runner.ed25519.pub \
  --paths build/test_signing_key.pem \
  --paths build/test_ssh_key

# Final verification (show recent commits)
for ref in $(git for-each-ref --format='%(refname)' refs/heads); do
  echo "--- $ref ---"
  git --no-pager log -n 3 --pretty=oneline "$ref" || true
done

read -p "Push cleaned history to origin (force)? [y/N] " yn
if [[ "$yn" =~ ^[Yy]$ ]]; then
  git push --force --all
  git push --force --tags
  echo "Force-push complete. Backup bundle: $BACKUP"
else
  echo "Push aborted. Backup bundle: $BACKUP"
fi

# Copy reports back to OUTDIR for review
cp -v "$GITLEAKS_REPORT" "$OUTDIR/" || true

echo "Done. Output directory: $OUTDIR"
