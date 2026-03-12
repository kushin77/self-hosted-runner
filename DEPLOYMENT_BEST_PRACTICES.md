# Deployment & CI/CD Best Practices

This concise checklist gathers recommended practices for CI/CD pipelines, Docker images, TypeScript builds, secrets management, and Cloud Build usage.

## CI/CD
- Use immutable artifact tags (short commit SHAs) for images and releases.
- Fail fast in early stages: run lint, unit tests, and SCA before packaging.
- Keep pipelines idempotent and declarative; safe to re-run.
- Add smoke/canary verification and automated rollback on failure.

## Cloud Build
- Always supply substitutions referenced in `cloudbuild.yaml` (use defaults or guard logic).
- Keep your uploads small via `.gcloudignore` and avoid sending large artifacts.
- Push scanned and signed images to Artifact Registry and publish SBOMs.

## Docker & Images
- Use multi-stage builds: compile in `builder` stage, copy only runtime artifacts.
- Pin base images and dependency versions; refresh pins via automation.
- Run container processes as a non-root user and set minimal file permissions.
- Add lightweight HTTP healthchecks and respect container liveness/readiness.

## TypeScript Builds
- Treat compilation errors as actionable bugs — do not ship long-term workarounds.
- Use `npm ci` with lockfile for deterministic installs and cache node_modules in CI.
- Enable incremental builds or cache tsc outputs to speed CI iterations.

## Secrets & Runtime Configuration
- Never bake secrets into images or commit them to source control.
- Inject secrets at runtime using Secret Manager, Vault Agent, or mounted token files.
- Apply least-privilege IAM to build and deploy service accounts.

## Observability & Security
- Emit structured logs and correlation IDs; include health/metrics endpoints.
- Integrate image scanning (Trivy, Container Analysis) and vulnerability gating.
- Generate and store SBOMs alongside released artifacts.

## Operational Notes
- Ensure relevant accounts have `storage.objects.get` for Cloud Build logs access or centralize logs to a permitted bucket.
- Pin images in infra (Terraform/Helm) and promote images from staging to prod through a controlled workflow.

---
For actionable follow-ups: I can (a) add gated CI checks to `cloudbuild.yaml`, (b) create a PR that pins base images, or (c) open issues to fix the TypeScript errors. Which do you prefer? 

## Image Signing (Cosign)

Recommendation: sign production images with `cosign` and verify signatures at deploy-time.

Cloud Build example (optional step after image push):

```yaml
# Add substitution: _COSIGN_KMS_URI: ''
- name: 'gcr.io/sigstore/cosign/cosign:2.1.0'
	entrypoint: 'bash'
	args:
	- '-c'
	- |
		if [ -n "${_COSIGN_KMS_URI:-}" ]; then
			cosign sign --key "${_COSIGN_KMS_URI}" us-central1-docker.pkg.dev/$PROJECT_ID/production-portal-docker/nexus-shield-portal-backend:${_SHORT_SHA}
			cosign sign --key "${_COSIGN_KMS_URI}" us-central1-docker.pkg.dev/$PROJECT_ID/production-portal-docker/nexus-shield-portal-frontend:${_SHORT_SHA}
		else
			echo "Skipping cosign: no _COSIGN_KMS_URI provided"
		fi
```

Operational notes:
- Use KMS-backed keys (Google Cloud KMS) for cosign keys and grant the Cloud Build service account `roles/cloudkms.signerVerifier` on the key.
- Verify image signatures at deploy-time (for managed deploys or k8s admissions).
