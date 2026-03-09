Image Rotation Risk Assessment

Scope:
- Automated rebuilds on Trivy HIGH/CRITICAL findings.

Risks & Mitigations:
- False positives causing unnecessary promotions: thresholding + manual PR review by default.
- Broken images promoted: require integration tests and canary promotion before full pin update.
- Secret/key exposure during signing: protect cosign keys in Vault/GSM/KMS and retrieve via OIDC at runtime.
- Rollback: keep previous image tags in `deploy/promoted-images.txt` and support automated rollback Draft issues.

Operational Controls:
- Immutable artifacts: all images are tagged and retained in registry with content-addressable references.
- Ephemeral creds: use OIDC to fetch Vault/GSM secrets; no long-lived tokens in repo.
- Audit: log dispatch events, promotions, and Terraform pin updates in Git history and CI artifacts.

Acceptance Criteria:
- Rebuilds are gated by tests and SBOM verification.
- Promotions create Draft issues for review (optional auto-merge after X approvals).
- Keys used for signing are stored only in Vault/GSM/KMS and rotated periodically.
