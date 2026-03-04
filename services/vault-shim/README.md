# Vault Dev Shim

Lightweight in-memory Vault-like shim for local development and testing of `managed-mode` secrets flows.

Usage:

```bash
cd services/vault-shim
npm ci
npm start
```

Features:
- Simple in-memory KV v1-like endpoints for dev and CI
- Token-based auth emulation: accepts `X-Vault-Token` or `Authorization: Bearer <token>`
- Optional namespace emulation via `X-Vault-Namespace` header (prefixes stored keys)

Endpoints (dev only):
- `PUT /v1/secret/:key` — store value (JSON body `{"value": ...}` or raw) (requires token header)
- `GET /v1/secret/:key` — retrieve value (requires token header)
- `DELETE /v1/secret/:key` — remove value (requires token header)

Notes:
- Default dev token is `root` (change via `VAULT_DEV_TOKEN` environment variable).
- To emulate namespaces add header `X-Vault-Namespace: myteam` and the stored key will be saved as `myteam:your-key`.
- This shim is NOT secure and only intended for local development. Use a real Vault instance in staging/production.
