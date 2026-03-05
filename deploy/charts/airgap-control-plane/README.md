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

Using the image-load Job
------------------------

The chart includes a scaffold Job template `templates/image-load-job.yaml` which expects a PVC containing image tarballs mounted at `/images`.
Set the following values in your chart `values.yaml` before installing:

- `imageLoader.image`: an image that contains `ctr`/`docker`/`podman` and the required tooling (or use the provided helper script to load and push images from a connected host).
- `imageLoader.pvc`: the name of a `PersistentVolumeClaim` where operators will upload `*.tar` files.
- `imagePullSecrets.enabled` and `imagePullSecrets.dockerconfigjson` (base64) to create a `dockerconfigjson` secret for private registries.

Operator flow (example):

1. Create a PVC `airgap-images-pvc` (small size) and make it writable by an operator.
2. Transfer tarballs to a bastion in the air-gapped network and copy them into the PVC (via `kubectl cp` or an init job).
3. Install the Helm chart with `--set imageLoader.pvc=airgap-images-pvc` and set `imageLoader.image` to a small tooling image (e.g., a BusyBox with `ctr` preinstalled).
4. Run the `image-load` Job to import images into cluster local store and optionally tag/push them to an on-prem registry.

See `scripts/airgap/load_images_to_registry.sh` for a small helper that loads tarballs locally and pushes them to a target registry from a connected host.

