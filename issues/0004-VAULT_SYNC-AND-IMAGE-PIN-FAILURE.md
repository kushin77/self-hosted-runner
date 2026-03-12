Title: TROUBLE: automation-runner vault_sync failed; image-pin-service startup failed
Status: open
Milestone: Phase 5 (Multi-Cloud Vault Integration)
Blocker-for-Milestone-4: NO — Phase 5 task; no impact on current deployment
Labels: incident, blocker, automation

Observed
--------
- Attempted GSM→Vault `vault_sync` via automation-runner returned:

```
ERROR: no Vault authentication available (set a token file, AppRole role_id+secret_id, or other Vault auth)
```

- `image-pin-service` deployments failed with container startup errors; Cloud Run logs show revision container failed to start/listen on expected port. Audit entries show service replace/create events.

Immediate cause
-------------
- Vault AppRole not provisioned and `VAULT_ADDR` not configured for automation-runner — AppRole provisioning is tracked in `issues/0001*` and `issues/0002*`.
- `image-pin-service` container likely misconfigured to listen on non-default port or healthcheck timing; Cloud Run reported the container didn't bind to `PORT=8080` within the timeout.

Action items
------------
1. Provision AppRole `automation-runner` (see `issues/0001-REQUEST-VAULT-ADDR-AND-ADMIN-TOKEN.md`) so automation-runner can authenticate to Vault. Then re-run `vault_sync`.
2. Inspect container startup logs for `image-pin-service` revision (detailed logs available in Cloud Logging). Quick checks:
   - Confirm container listens on `$PORT` (8080) or set `PORT` env accordingly.
   - Increase Cloud Run startup timeout if container needs more time.
   - Test container locally: `docker run -p 8080:8080 <image>` and curl health endpoint.

Links
-----
- automation-runner: https://automation-runner-2tqp6t4txq-uc.a.run.app
- image-pin-service: https://image-pin-service-2tqp6t4txq-uc.a.run.app

Assignee: @operator / @automation
