Air-gap automation: next steps and local testing

- Start a local OTEL Collector for end-to-end exporter tests:
  - `cd deploy/otel && docker compose up -d`
  - Use existing `scripts/send_otlp.sh` (or `services/*/tests/send_otlp.sh`) to send test telemetry and check collector logs.

- Terraform module improvements to make:
  - Add provider configuration and image preloading steps for offline registries.
  - Add variables for registry mirrors, CA certs, and imagePullSecrets.

- Helm chart improvements:
  - Add templates for preloaded images, imagePullSecrets, and certificate management.
  - Add a `collector.enabled` toggle (already present); set `collector.enabled=true` for verification.

- Follow-ups (create GitHub issues):
  - Flesh out air-gap Terraform module with image preload automation.
  - Add CI job to run a kind cluster and validate helm+tfplan in air-gapped mode.
