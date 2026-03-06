PMO Automation README
=====================

Quick commands for safe operations and local immutable testing.

Back up repository (creates timestamped tar.gz in `artifacts/backups`):

```bash
bash scripts/automation/pmo/backup-repo.sh
```

Dry-run controlled nuke-and-restore (non-destructive):

```bash
bash scripts/automation/pmo/nuke-and-restore.sh --target 192.168.168.42 --user cloud
```

Perform controlled nuke-and-restore (DESCTRUCTIVE — requires `--confirm`):

```bash
bash scripts/automation/pmo/nuke-and-restore.sh --target 192.168.168.42 --user cloud --confirm
```

Local immutable test using `docker-compose` (requires Docker or Podman compat):

```bash
cd scripts/automation/pmo
docker compose up --build
```

CI: The workflow `.github/workflows/ci-images.yml` builds images and pushes them to the registry configured via GitHub secrets: `REGISTRY_HOST`, `REGISTRY_USERNAME`, `REGISTRY_PASSWORD`.

Next steps:
- Add registry secrets to repository
- Containerize other services if present
- Replace ad-hoc starts with systemd unit templates or GitOps reconciler
