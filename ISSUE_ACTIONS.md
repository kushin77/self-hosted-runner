Planned GitHub issue actions (requires GitHub token / owner confirmation):

- EPIC-2: Implement Unified Migration API & Controller
  - Create issue: "EPIC-2: Unified Migration API — implement job queue, auth, MFA"
  - Assign labels: epic, backend, security

- EPIC-2.1: API Auth & RBAC
  - Create issue: "EPIC-2.1: API Auth — OIDC JWKS + admin bootstrap removal"

- EPIC-2.3: Durable Job Store / Queue
  - Create issue: "EPIC-2.3: Durable Job Store — Redis worker TLS and HA or Pub/Sub migration"

- EPIC-3: Browser Migration Dashboard
  - Update issue: mark as completed (static dashboard served from Flask); add follow-ups for React/Vite port

Notes: run the following to create issues via GitHub CLI (or use API):

  gh issue create --repo <owner>/<repo> --title "EPIC-2: Unified Migration API — implement job queue, auth, MFA" --body "..." --label epic,backend

Confirm owner/repo and whether you want me to create/close these issues programmatically. If yes, provide GitHub credentials or allow me to use `gh` in this environment.
