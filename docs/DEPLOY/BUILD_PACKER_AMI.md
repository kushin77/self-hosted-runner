# Build & Validate Ollama-enabled Runner AMI

This guide documents steps to build the Packer AMI that includes Ollama and to validate the resulting runner images in staging.

Prerequisites
- Packer installed (recommended >= 1.8)
- Cloud provider credentials configured (AWS/GCP/Azure) for Packer
- SSH keypair for staging instance access
- Access to repo branch: `feature/ci-portal-staging-e2e`

1) Build AMI

From the repository root run:

```bash
./scripts/build-ami.sh
```

For a dry-run (print command but do not execute):

```bash
./scripts/build-ami.sh --no-run
```

2) Launch staging instances
- Use your normal environment tooling (Terraform, cloud console, or CLI) to launch instances from the created AMI.
- Ensure instances have network access to GitHub and to any internal services required for registration.

3) Validate Ollama service on each runner

SSH into the instance and run:

```bash
sudo systemctl status ollama --no-pager
curl -sS http://localhost:11434/api/models | jq .
```

Expected results:
- `systemctl` shows `active (running)` for `ollama.service`.
- `curl` returns JSON with at least one model entry.

4) Register runners with GitHub
- Use your standard self-hosted runner registration flow to connect staging runners to the repo or org.

5) Run integration tests on a staging runner

SSH to the staging runner and run the integration test suite from the repo checkout (or run from a CI controller and target the runner):

```bash
cd /path/to/self-hosted-runner
./tests/integration-agentic-workflows.sh
```

6) Validate auto-fix workflow end-to-end

Create a test branch and PR that contains a small intentionally-broken file (e.g., missing semicolon or TODO comment) and push it. Example:

```bash
git checkout -b test/auto-fix-demo
printf "console.log('broken' )\n" > broken.js
git add broken.js
git commit -m "test: add broken file to trigger auto-fix workflow"
git push -u origin test/auto-fix-demo
# Open a PR via GitHub UI or `gh pr create` and watch Actions tab for auto-fix.lock.yml
```

7) Troubleshooting
- If `ollama` is not running, check `/var/log/ollama` or `journalctl -u ollama -n 200` for errors.
- If models don't appear, ensure model files are present under the configured models directory and permissions are correct.
- If runners don't pick up jobs, ensure runner labels include `elevatediq-runner` and the runner is online.

8) Post-validation
- If all verification steps pass, mark the tracking task in `docs/ISSUES/DEPLOY_OLLAMA_AMI.md` as done and consider promoting the AMI to production use.
