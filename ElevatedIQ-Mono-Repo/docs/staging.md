# Staging Setup and API Base Configuration

> **Note:** the portal dev server binds to `0.0.0.0` and defaults to port
> **3919**, making it accessible from other hosts on the LAN (e.g.
> `http://192.168.168.42:3919`). You may override the port via `PORT`.


This document explains how to run the Portal against a staging backend and how to configure the runtime API base and mock toggle.

Environment variables
- `VITE_USE_MOCK` (default: `true` locally): when `true`, the portal uses in-client mock data and does not call external APIs.
- `VITE_API_BASE` (default: empty): prefix for API fetches when `VITE_USE_MOCK=false`. Example: `https://staging-api.example.com` or `http://localhost:4000`.

Local developer steps
1. Use the local mock-server (default):

```bash
# in repo root
cd ElevatedIQ-Mono-Repo/apps/portal
cp .env.example .env
# start Vite dev server (uses mocks by default)
pnpm install --frozen-lockfile
pnpm dev
```

2. Run the portal against a staging backend

Set `VITE_USE_MOCK=false` and `VITE_API_BASE` to your staging URL before building/running:

```bash
# example: use staging API
export VITE_USE_MOCK=false
export VITE_API_BASE=https://staging-api.example.com
pnpm dev
```

Or with an .env file in `apps/portal`:

```
VITE_USE_MOCK=false
VITE_API_BASE=https://staging-api.example.com
```

CI / Staging environment
- Set `VITE_API_BASE` in the staging environment or Actions job to point at the staging API.
- Keep `VITE_USE_MOCK` set to `false` for integration runs.
- Use the `mock-server-smoke.yml` workflow for PR-level streaming validation; use the `mock-server-nightly.yml` for scheduled validation.

Security and secrets
- Do not store production credentials in the repo; add secrets to GitHub Actions or the staging platform's secrets manager.

Troubleshooting
- If API calls return CORS errors, ensure the staging API allows the portal origin or proxy through the development server.
- Use the mock-server logs for debugging if `VITE_USE_MOCK=true`.

Contact
- For Phase‑3 integration questions see issue #69.
