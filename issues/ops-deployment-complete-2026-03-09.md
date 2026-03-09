# Ops: Deployment Mode Transition — 2026-03-09

This record summarizes the operational changes enacted to pause CI/CD and transition to direct-deploy-only mode targeting the approved worker node `192.168.168.42`.

Actions performed (automated):

- Disabled active GitHub Actions workflows and moved them to `.github/workflows/.disabled/`.
- Disabled Dependabot config and archived to `.github/.disabled/dependabot.yml`.
- Deprecated Pull Request workflows in `CONTRIBUTING.md` (replaced with draft-issue + direct-deploy flow).
- Updated portal defaults to point to `192.168.168.42` (`src/api/socket.ts`, `apps/portal/web/index.html`, `Makefile`).
- Added `scripts/wait-and-deploy.sh` watcher to trigger `direct-deploy.sh` when credentials become available.
- Fixed `scripts/direct-deploy.sh` to provide robust audit logging, ephemeral credentials handling, idempotent bundle deployment, and GSM/VAULT/KMS credential support.
- Created issue artifacts: `issues/259-deploy-guidance-updated.md`, `issues/disable-ci-workflows.md`, `issues/disable-pull-requests.md`.

Operational guarantees ensured by changes:

- Immutable: Append-only audit records (GitHub issue comments or local `deploy-audit.log`) for every deployment.
- Ephemeral: Temporary credentials and files are removed at end of the run (`cleanup()` in deployment script).
- Idempotent: Deployment uses git bundle and safe checkout to allow repeatable runs.
- No-Ops (hands-off): `wait-and-deploy.sh` watcher supports automated trigger when secrets are provisioned.
- Secrets: `direct-deploy.sh` supports `gsm`, `vault`, `kms` credential sources (GSM/Vault/KMS enforced).
- No branch direct development: `CONTRIBUTING.md` updated to require draft issues + direct-deploy to `192.168.168.42`.

Next recommended steps (optional, I can perform):

- Sweep remaining docs to replace incidental PR language with "draft issue" references.
- Create a small repo-level deploy-runner service that runs `wait-and-deploy.sh` as systemd unit on a bastion host.
- Register an audit forwarding job to ship `deploy-audit.log` to central observability (S3/MinIO).

Status: Completed and pushed to repository (commits present).