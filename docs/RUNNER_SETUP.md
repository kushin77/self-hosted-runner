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
