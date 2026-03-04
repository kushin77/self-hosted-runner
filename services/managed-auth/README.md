# RunnerCloud Managed Auth (OAuth) - Skeleton

This folder contains a minimal Node.js express skeleton that implements the OAuth redirect and callback endpoints used for the GitHub App signup flow.

This is a starting point — implement secure token exchange, state validation, and runner provisioning logic here.

Endpoints:
- `GET /auth/github` — redirect to GitHub OAuth authorize URL (placeholder)
- `GET /auth/github/callback` — OAuth callback handler (placeholder)

To run locally (dev):

```bash
cd services/managed-auth
npm install express
node index.js
```

