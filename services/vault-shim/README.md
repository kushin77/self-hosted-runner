# Vault Dev Shim

Lightweight in-memory Vault-like shim for local development and testing of `managed-mode` secrets flows.

Usage:

```bash
cd services/vault-shim
npm ci
npm start
```

Endpoints (dev only):
- `PUT /v1/secret/:key` — store value (JSON body `{"value": ...}` or raw)
- `GET /v1/secret/:key` — retrieve value
- `DELETE /v1/secret/:key` — remove value

Notes:
- This shim is NOT secure and only intended for local development. Use a real Vault instance in staging/production.
