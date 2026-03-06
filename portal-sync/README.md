# Portal Sync: ingestion and usage

This folder contains artifacts and tooling to keep the Portal in sync with backend capabilities.

What this does
- `function-metadata.schema.json` — canonical schema for per-function metadata
- `metadata-template.yaml` — developer template to copy into each function folder
- `scripts/generate_function_metadata.py` — scanner and validator that produces `portal-artifact.json`

Developer flow
1. When you add a new function, copy `portal-sync/metadata-template.yaml` into the function folder and update fields.
2. Add the metadata YAML to your PR. CI (`portal-sync-validate` workflow) will validate and fail the PR if required fields are missing.
3. Portal ingests `portal-artifact.json` produced by CI or pulls directly from the backend introspection endpoints.

Operational notes
- Portal ingestion can either pull introspection endpoints from services or consume the CI `portal-artifact.json` artifact.
- Do not store secrets in metadata.

Integration options for the Portal team
- Pull from backend: GET `/api/v1/introspect/functions` (recommended for real-time view).
- Pull from CI artifact: download `portal-artifact.json` from CI artifacts for nightly aggregation.
- CI → Webhook: Configure CI to POST the artifact JSON to the webhook receiver `POST /webhook` on the portal ingestion host. The webhook verifies `X-Hub-Signature-256` HMAC against `PORTAL_WEBHOOK_SECRET` and will call the ingestion script.

Webhook receiver
- A minimal webhook receiver is available at `portal-sync/webhook_receiver.py`. It expects a JSON body containing the artifact (or the artifact can be supplied under the `artifact` key). Set `PORTAL_WEBHOOK_SECRET` and run the server on a reachable host.

Ingestion
- `portal-sync/ingest_to_portal.py` will POST the artifact to `PORTAL_URL` using `PORTAL_TOKEN` if provided, or save `portal-sync/last-ingested.json` locally for manual pickup.

Developer pre-commit
- To install a local pre-commit hook that validates metadata before commits run:

```bash
./tools/install-metadata-hook.sh
```

