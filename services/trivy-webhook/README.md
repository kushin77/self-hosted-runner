Trivy Webhook Receiver

- Endpoint: `POST /trivy-webhook`
- Uses `TRIVY_WEBHOOK_SECRET` (or `WEBHOOK_SECRET`) to verify HMAC sha256 signatures.
- Uses `GITHUB_TOKEN` and `DISPATCH_REPO` (or `GITHUB_REPOSITORY`) to issue repository dispatches (event_type `trivy_alert`).
- Configurable thresholds: `THRESH_CRITICAL`, `THRESH_HIGH`.

Run locally:

```bash
cd services/trivy-webhook
npm install
TRIVY_WEBHOOK_SECRET=shh GITHUB_TOKEN=$GITHUB_TOKEN node index.js
```
