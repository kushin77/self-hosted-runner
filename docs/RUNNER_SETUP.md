# Runner Setup (mimic of ElevatedIQ-Mono-Repo)

This repository includes a minimal portal that models runner management similar to `ElevatedIQ-Mono-Repo`.

Server (API): `apps/portal/server`
- Start: `cd apps/portal/server && npm install && npm start`
- Provides endpoints:
  - `GET /api/runners` — list
  - `POST /api/runners` — register { name, labels }
  - `DELETE /api/runners/:id` — remove

Web UI: `apps/portal/web/index.html`
- A tiny client to register and remove runners. Open in browser and point to `http://localhost:4000`.

Org-level runner registration (GitHub):
- Get an org registration token as an org admin:

```bash
gh api --method POST /orgs/elevatediq-ai/actions/runners/registration-token
```

- On runner host, stop existing service and remove the current registration, then reconfigure with org URL and token:

```bash
# stop service (if installed)
./svc.sh stop || true
./config.sh remove || true

# register to elevatediq-ai org
./config.sh --url https://github.com/elevatediq-ai --token <TOKEN> --unattended --name "org-runner-01" --labels "linux,self-hosted"
./svc.sh install
./svc.sh start
```

Notes:
- Registration scope is determined at `config.sh` time (repository vs organization).
- This portal is a minimal mimic to manage runner metadata; it does NOT perform the actual GitHub runner registration — that must run on the host where the runner process runs.

Publishing the portal image
-------------------------

We provide a CI workflow to build and publish the portal Docker image to GitHub Container Registry on pushes to `main`.
The workflow file is `.github/workflows/publish-portal-image.yml` and is configurable to use a fine-grained PAT stored in the repo secret `GHCR_PAT` (recommended for production). For development the workflow also supports `GITHUB_TOKEN`.

Monitoring / Alerts
-------------------

A lightweight notification helper is available at `scripts/notify_health.sh` which posts messages to a Slack webhook defined in `SLACK_WEBHOOK`.
The systemd healthcheck may call this script when reprovisioning occurs; configure a secure webhook in your environment before enabling alerts.

Rotation and secrets
--------------------

For production, do NOT rely on a local `gh` auth state. Use one of these approaches:

- Store a fine-grained PAT with `packages:write` in GitHub Actions or in a secrets manager and set the repo secret `GHCR_PAT` (used by CI to publish images).
- Use `scripts/rotate_ghcr_pat.sh` to programmatically update the repo secret when you rotate tokens. Example:

```bash
# rotate: provide new token in GHCR_PAT env and run script
GHCR_PAT="ghp_xxx..." ./scripts/rotate_ghcr_pat.sh --repo kushin77/self-hosted-runner
```

- When promoting to prod, move the persistent credential into Vault or a secure secrets store and give the CI an ephemeral access path.

Vault integration example
-------------------------

We provide an example GitHub Actions workflow that demonstrates fetching `GHCR_PAT` from HashiCorp Vault using OIDC and the `hashicorp/vault-action`. See `.github/workflows/vault-secrets-example.yml` for a sample.

Required pieces:
- A Vault server reachable from GitHub Actions (`VAULT_ADDR` secret).
- A Vault role configured to accept GitHub OIDC tokens and allow reading `secret/data/ci/ghcr#GHCR_PAT`.
- The workflow demonstrates exporting the secret into `env.GHCR_PAT` which is then used to login to GHCR during the build.

This pattern avoids storing long-lived PATs in repo secrets and enables rotation and audit in Vault. Full production integration requires configuring Vault policies and the OIDC role — track that work in issue #794.

Healthchecks & Automated Reprovisioning
--------------------------------------

To keep the org-level runner sovereign, ephemeral, and self-healing we provide a systemd `oneshot` service and a `timer` that runs a healthcheck and reprovision script every 5 minutes. The script detects when the runner is missing or offline and re-runs `scripts/provision_org_runner.sh` to register a new ephemeral runner.

Files added:
- `scripts/check_and_reprovision_runner.sh` — checks runner status and reprovisions when needed.
- `systemd/actions-runner-health.service` — systemd unit (oneshot) that runs the check script.
- `systemd/actions-runner-health.timer` — systemd timer that triggers the unit every 5 minutes.

To install and enable the timer on the host (one-time; requires sudo):

```bash
# from repo root
chmod +x scripts/install_systemd_timer.sh
sudo scripts/install_systemd_timer.sh

# verify
sudo systemctl status actions-runner-health.timer --no-pager
```

Security notes
- The reprovision flow uses the `gh` CLI for ephemeral registration tokens; the one-time registration token is short-lived and not stored. The persistent credential used by `gh` (the PAT) should be stored/rotated according to your org policy. For dev usage the current `gh` auth was used; rotate the PAT before promoting to production.

If you want me to enable the timer now and commit the systemd files to the repo, say "install timer" and I'll do it for you.

