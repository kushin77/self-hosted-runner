No GitHub Actions Policy

This repository follows a strict "no GitHub Actions" policy to ensure centralized, auditable, and compliant CI/CD via Cloud Build and our ops pipelines.

What to do if you find a workflow file
- Do NOT enable/run it.
- Move file(s) to `archived_workflows/<timestamp>/` and reference them in an issue describing why they were archived.
- Open an issue tagging @kushin77 and @BestGaaS220 describing the archived workflow and any required replacements.

Why:
- Centralized control: Cloud Build provides enterprise-grade controls and integration with GSM/Vault/KMS.
- Security: prevents accidental leaking of secrets into GitHub Actions variables.
- Compliance: enforces artifact signing and immutable storage patterns.

If you need a CI change, open an ops issue and link the Cloud Build job or template.
