Portal Mock Server

This folder contains a small Express mock server that implements the `/api/*` endpoints used by the portal UI during local development.

Quick start

1. Install deps

```bash
cd apps/portal/mock-server
npm install
```

2. Run server

```bash
npm run start
```

Server will listen on `http://localhost:3001` and expose:
- `/api/runners`
- `/api/events`
- `/api/billing`
- `/api/cache`
- `/api/ai`
- `/api/agents`

How to use with the portal UI

The portal client uses an in-client mock by default. To point the portal to this mock server for local end-to-end testing:

- Set the Vite env var `VITE_API_USE_MOCK=false` and `VITE_API_BASE=http://localhost:3001` when running the portal dev server.

For example (bash):

```bash
# start mock server in one terminal
cd apps/portal/mock-server
npm install
npm run start

# start the portal dev server in another terminal, pointing to the mock
VITE_API_USE_MOCK=false VITE_API_BASE=http://localhost:3001 pnpm dev
```

If you prefer to keep the in-client mock, no changes are needed.
