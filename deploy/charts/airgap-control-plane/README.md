Air-gap Control Plane Helm Chart
================================

This chart is a lightweight scaffold for deploying an OpenTelemetry collector and related control-plane components into an air-gapped environment.

Preload images
---------------
Use the provided preload script to pull required images on an internet-connected host and export them as tarballs for transfer to the air-gapped network:

1. Create an `images.txt` with one image per line (example below).
2. Run `scripts/airgap/preload_images.sh images.txt /tmp/images`
3. Transfer `/tmp/images/*.tar` to the air-gapped host and load with `docker load -i ...` or `podman load -i ...`.

Example `images.txt`:

```
quay.io/opentelemetry/opentelemetry-collector-contrib:0.58.0
ghcr.io/datadog/agent:latest
ghcr.io/splunk/splunk-otel-collector:latest
```

Next steps
----------
- Add imagePullSecrets and private registry configuration for your air-gapped registry.
- Implement image verification (sha256) and a manifest file to validate transferred images.
- Add a small controller or job to load tarballs into the local registry and verify checksums.
