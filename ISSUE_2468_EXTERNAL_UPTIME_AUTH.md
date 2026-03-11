Title: Phase 4.3 - External uptime checks need authenticated probes

Description:
- External uptime checks currently receive HTTP 401 due to org policy (`constraints/run.allowUnauthenticatedAccess`).
- Options:
  - Implement service-account-based authenticated probes (preferred): create a short-lived service account token or signed JWT grid for Monitoring uptime checks.
  - Request org policy exception to allow specific uptime-checker identity.
  - Use internal verified probes from within the VPC or trusted network.

Acceptance Criteria:
- Uptime checks return HTTP 200 for backend `/health` and frontend root using approved authentication method.
- Implementation is idempotent and uses GSM/Vault/KMS for any credentials.

Notes:
- Tracked as follow-up; implementation requires org-level decision or additional infra for probe authentication.
