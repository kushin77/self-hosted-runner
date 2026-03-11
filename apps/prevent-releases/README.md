Prevent Releases App
====================

Purpose: lightweight GitHub App to remove releases and tags immediately and create an audit issue so server-side policy is enforced.

Deployment notes:
- Create a GitHub App in the organization or user account with:
  - Webhook URL: your app endpoint (Cloud Run / HTTPS)
  - Webhook secret
  - Permissions: Repository -> Contents (read/write) or Repository -> Metadata + Issues (write) and Repository -> Actions (none)
  - Subscribe to events: Create, Release

- Store the private key and app id in GSM (example secret names: `github-app-private-key`, `github-app-id`).
- Deploy container to Cloud Run with environment variables wiring to fetch private key and app id.

Security: keep the app private key in GSM and grant Cloud Run SA `roles/secretmanager.secretAccessor`.
