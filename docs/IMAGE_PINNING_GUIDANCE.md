Image Pinning Guidance

- Use pinned image tags or digests in Terraform: provide `image_tag` variable and set it from promoted PRs.
- Prefer content-addressable digests: `ghcr.io/org/image@sha256:...` when possible.
- Implement canary promotion: update canary deployments first, run smoke tests, then update production pins.
- Keep a changelog file for promoted images (`deploy/promoted-images.txt`) for auditability.
- Automate PR creation for pin updates; require at least one human approval before auto-merge in production.
