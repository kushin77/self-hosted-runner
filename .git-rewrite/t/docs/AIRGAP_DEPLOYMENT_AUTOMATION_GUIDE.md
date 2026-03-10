# Air-Gap Deployment Automation Guide

This guide describes the air-gap automation workflows and scripts provided in this repository for deploying and validating infrastructure in isolated or restricted network environments.

## Overview

Air-gap deployments require pre-pulling container images and storing them for transport to the target environment. This repository provides scripts and CI workflows to:

1. **Generate** image manifests listing all required container images
2. **Preload** images from public registries and save as tarballs
3. **Load** tarballs into a local/private registry 
4. **Verify** images are available in the target registry
5. **Sign & Verify** images using cosign (optional, for enhanced security)

## Scripts

### Generate Manifest

Generate a manifest of required container images:

```bash
./scripts/airgap/generate_image_manifest.sh > deploy/airgap/manifest.yml
```

Edit `deploy/airgap/manifest.yml` to include all images required for your deployment (services, dashboards, monitoring, etc.).

### Preload Images

Pull all images from the manifest and save as local tarballs:

```bash
./scripts/airgap/preload_images.sh deploy/airgap/manifest.yml build/airgap-images
```

This creates tar files like `build/airgap-images/grafana_grafana_9.5.6.tar` for each image.

**Note:** This step requires internet access and sufficient disk space. Run this in an environment with pulling privileges.

### Load to Registry

Load saved tarballs and push to a target private registry:

```bash
./scripts/airgap/load_images_to_registry.sh my-registry.local:5000 build/airgap-images
```

This requires:
- Docker credentials configured for `my-registry.local:5000`
- Write access to the registry
- The local docker daemon running

### Verify Registry Images

Verify all images are available in the target registry:

```bash
./scripts/airgap/verify_images.sh my-registry.local:5000 deploy/airgap/manifest.yml
```

### Generate Checksummed Manifest

Generate a manifest with image digests:

```bash
./scripts/airgap/generate_manifest_checksums.sh deploy/airgap/manifest.yml deploy/airgap/manifest-checked.yml
```

This extracts `sha256:...` digests for each image and adds them to the manifest for integrity verification.

### Sign Images (Optional)

Sign images with cosign for supply-chain security:

```bash
export COSIGN_KEY_FILE=/path/to/cosign.key
./scripts/airgap/sign_images_cosign.sh deploy/airgap/manifest-checked.yml /path/to/cosign.key
```

**Prerequisites:**
- `cosign` binary installed
- Private key file (PEM format)
- Images must be pushed to a registry (e.g., Docker Hub, GitHub Container Registry)

### Verify Signatures (Optional)

Verify cosign signatures:

```bash
export COSIGN_PUB_KEY_FILE=/path/to/cosign.pub
./scripts/airgap/verify_signatures_cosign.sh deploy/airgap/manifest-checked.yml /path/to/cosign.pub
```

## CI Workflows

### Image Validation Workflow

**File:** `.github/workflows/ci-airgap-validate.yml`

Runs on:
- Pull requests to `main`
- Manual dispatch (via GitHub Actions UI or `gh workflow run`)

Steps:
1. Generate manifest from source
2. Pull all listed images (validates registry access)
3. Generate checksummed manifest
4. Optionally sign images (if `COSIGN_KEY` secret is available)
5. Optionally verify signatures (if `COSIGN_PUB_KEY` secret is available)

### Full Integration Test Workflow

**File:** `.github/workflows/ci-airgap-full-test.yml`

Runs on:
- Push to `main`
- Pull requests to `main`
- Manual dispatch
- Weekly schedule (Sunday 03:30 UTC)

Steps:
1. Generate manifest
2. **Preload** all images
3. Generate checksummed manifest
4. Start a local Docker registry container
5. **Load** images into local registry
6. **Verify** all images pull from local registry
7. Archive sample tarballs as CI artifacts
8. Cleanup

This workflow provides end-to-end validation of the air-gap workflow, including tarball creation and local registry operations.

## GitHub Actions Secrets

To enable signing/verification in CI, configure these secrets in your GitHub repository settings:

- `COSIGN_KEY` — base64-encoded cosign private key (for signing)
- `COSIGN_PUB_KEY` — base64-encoded cosign public key (for verification)

Encode a key file with:
```bash
base64 -i cosign.key -o - | xclip -selection clipboard
```

Then paste into the GitHub secret value.

## Workflow

Typical air-gap deployment workflow:

1. **Develop & Test locally:**
   - Update `deploy/airgap/manifest.yml` with new images
   - Commit and push to a feature branch
   - CI automatically validates manifest and pulls images

2. **Prepare for air-gap:**
   - Merge changes to `main` (triggers full integration test)
   - Review CI test results and artifact tarballs
   - Download or replicate tarballs for transport to air-gap environment

3. **Deploy to air-gap:**
   - Copy tarballs to air-gap environment
   - Use `./scripts/airgap/load_images_to_registry.sh` to load into private registry
   - Run `./scripts/airgap/verify_images.sh` to confirm all images available
   - Deploy applications referencing `my-registry.local:5000/...` image URLs

4. **Optional: Verify signatures** (post-deployment)
   - Run `./scripts/airgap/verify_signatures_cosign.sh` in the air-gap to confirm image integrity

## Integration with Deployment Tools

### Helm

Update `charts/airgap-control-plane/values.yaml` or chart templates to use the private registry:

```yaml
spec:
  containers:
  - name: collector
    image: my-registry.local:5000/otel/opentelemetry-collector-contrib:0.80.0
    imagePullSecrets:
    - name: private-registry-secret
```

### Terraform

Use the private registry in Terraform configurations:

```hcl
resource "docker_image" "collector" {
  name = "my-registry.local:5000/otel/opentelemetry-collector-contrib:0.80.0"
}
```

## Troubleshooting

**Q: `preload_images.sh` fails with "cannot pull image"**
- Ensure Docker daemon is running
- Verify internet access to Docker Hub or specified registries
- Check docker login credentials: `docker info` should show authenticated registries

**Q: `load_images_to_registry.sh` fails with "permission denied"**
- Check docker credentials for the target registry: `docker login my-registry.local:5000`
- Verify push permissions for the authenticated user
- Check network connectivity to the registry

**Q: `verify_images.sh` reports images missing**
- Confirm `load_images_to_registry.sh` completed successfully
- Check network connectivity between runner and registry
- Verify image names match between the manifest and registry (case-sensitive)

**Q: Cosign sign/verify fails in CI**
- Ensure `COSIGN_KEY` and `COSIGN_PUB_KEY` secrets are base64-encoded correctly
- Install cosign binary in the CI runner: `apt-get install -y cosign` (or similar)
- Verify cosign binary is in PATH: `which cosign`

## Related References

- OpenTelemetry Collector: https://github.com/open-telemetry/opentelemetry-collector
- Cosign: https://docs.sigstore.dev/cosign/overview/
- Grafana: https://grafana.com/
- Docker Registry: https://docs.docker.com/registry/
- Air-gap Deployment Best Practices: See `docs/AIRGAP_AUTOMATION_NEXT_STEPS.md`
