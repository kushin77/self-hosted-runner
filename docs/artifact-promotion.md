Artifact Promotion Workflow

Goals

- Deterministically promote only artifacts that have passed validation and are signed.
- Maintain full provenance, SBOM, vulnerability scan results, test reports, and signatures.

Workflow

1. Build Stage (L2)
   - Build produces artifact metadata: image digest, SBOM, build env hash, builder image, provenance.
   - Artifact is scanned and signed; metadata is pushed to artifact registry and attestation store (e.g., in-toto/rekor).

2. Validation (L3)
   - Validation engine runs tests; outputs SLO pass/fail and confidence score.
   - If pass, the artifact receives a promotable tag (e.g., `promotable/<commit-sha>`).

3. Promotion Decision
   - Promotion Controller checks telemetry and SLOs (automated), policy gates (e.g., OPA) and compliance rules.
   - If all gates pass, controller opens a GitOps PR with updated manifests referencing the signed digest.

4. Production Deployment (L4)
   - GitOps operator applies the change to the target cluster(s) following progressive rollout strategy.
   - The rollout controller monitors telemetry and can abort or rollback.

Guarantees

- Immutability: production references image digests, never floating tags.
- Audit trail: every promotion is recorded as a signed Git commit and attestation in an append-only log.
- Reproducibility: build environment hashes and SBOMs allow rebuild verification.

Implementation notes

- Use cosign for signatures and rekor for transparency logs.
- Store SBOMs alongside artifacts in a secured SBOM catalog service.
- Promotion controller must operate under least privilege and use ephemeral creds to open PRs.