#!/usr/bin/env bash
set -euo pipefail

REPO="kushin77/self-hosted-runner"
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
BRANCH_NAME="auto/deployment-package-${TIMESTAMP}"

info() { echo "[info] $*"; }

mkdir -p tmp_deploy_pkg

info "Generating RCA, operator guide, and master index..."

cat > tmp_deploy_pkg/RCA_MULTI_LAYER_HEALTH_CHECK_FAILURES.md <<'EOF'
# RCA: Multi-Layer Health Check (Automated Package)

This is an automatically generated RCA scaffold created on deployment.

Summary:
- Generated: ${TIMESTAMP}
- Note: This file is a template. The automated health-check workflow and remediation scripts are available.

Layers:
- GSM (GCP Secret Manager)
- Vault (HashiCorp Vault)
- KMS (AWS KMS)

Remediation steps and evidence are collected in the master index.
EOF

cat > tmp_deploy_pkg/OPERATOR_FINAL_GUIDE.md <<'EOF'
# Operator Final Guide (Automated)

This file contains the quick steps to complete remediation and validate the deployment.

1. Run the interactive remediation script:

```bash
bash scripts/remediate-secrets-interactive.sh
```

2. Monitor the health-check:

```bash
./scripts/monitor-health-run.sh
```

3. Confirm in the deployment issue created by automation.
EOF

cat > tmp_deploy_pkg/RCA_AND_REMEDIATION_PACKAGE.md <<'EOF'
# RCA And Remediation Package (Index)

Generated: ${TIMESTAMP}

- [RCA_MULTI_LAYER_HEALTH_CHECK_FAILURES.md](RCA_MULTI_LAYER_HEALTH_CHECK_FAILURES.md)
- [OPERATOR_FINAL_GUIDE.md](OPERATOR_FINAL_GUIDE.md)
- scripts: `scripts/remediate-secrets-interactive.sh`, `scripts/validate-secrets-preflight.sh`, `scripts/monitor-health-run.sh`
- Health-check workflow: `.github/workflows/secrets-health-multi-layer.yml`

Use this package as your single-pane operator handoff asset.
EOF

info "Copying existing scripts if present and ensuring executables..."
mkdir -p scripts
cp -f scripts/remediate-secrets-interactive.sh scripts/remediate-secrets-interactive.sh 2>/dev/null || true
cp -f scripts/validate-secrets-preflight.sh scripts/validate-secrets-preflight.sh 2>/dev/null || true
cp -f scripts/monitor-health-run.sh scripts/monitor-health-run.sh 2>/dev/null || true
chmod +x scripts/*.sh || true

info "Moving generated docs into repo root (idempotent)..."
for f in tmp_deploy_pkg/*; do
  base=$(basename "$f")
  cp -f "$f" "$base"
done

info "Committing generated package to repository..."
git config user.name "github-actions[bot]" || true
git config user.email "github-actions[bot]@users.noreply.github.com" || true
git checkout -b "$BRANCH_NAME" || git checkout "$BRANCH_NAME" || true
git add -A
git commit -m "chore(deploy): add automated deployment package ${TIMESTAMP}" || true
git push origin HEAD:main || git push origin HEAD

info "Creating/Updating deployment tracking issue..."
DEPLOY_BODY=$(cat <<EOB
Automated deployment package generated on ${TIMESTAMP}.

Files included:
- RCA_MULTI_LAYER_HEALTH_CHECK_FAILURES.md
- OPERATOR_FINAL_GUIDE.md
- RCA_AND_REMEDIATION_PACKAGE.md

Operator actions:
1. Run `bash scripts/remediate-secrets-interactive.sh` to set secrets.
2. Monitor the health-check using `./scripts/monitor-health-run.sh`.

This issue is created automatically and will be updated/closed by automation after successful health-check.
EOB
)

EXISTING=$(gh issue list --repo "$REPO" --label deployment --limit 5 --json number,title --jq '.[] | select(.title=="Automated: Deployment package generated") | .number' || true)
if [[ -n "$EXISTING" ]]; then
  info "Updating existing deployment issue #$EXISTING"
  gh issue comment "$EXISTING" --repo "$REPO" -b "$DEPLOY_BODY"
else
  gh issue create --repo "$REPO" --title "Automated: Deployment package generated" --body "$DEPLOY_BODY" --label "deployment,automation" || true
fi

info "Cleanup and done."
rm -rf tmp_deploy_pkg

echo "DEPLOY_PACKAGE_GENERATED=true"
