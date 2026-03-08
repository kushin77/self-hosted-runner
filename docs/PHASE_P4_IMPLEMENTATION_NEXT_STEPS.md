# Phase P4 — Implementation: Immediate Next Steps

This document lists concrete implementation actions to reach immutable, ephemeral, idempotent, fully automated control-plane and runner fleets.

Short-term priorities (this sprint):
- Provision Vault PKI and roles for mTLS (scaffold in `infra/vault/pki`).
- Deploy Envoy with cert provisioning via Vault (initContainer + Vault Agent examples in `control-plane/envoy`).
- Implement Vault Agent bootstrap and systemd unit for non-k8s environments (`control-plane/vault-agent`).
- Automate image scans with Trivy and define policy thresholds (see `.github/workflows/image-rotation.yml`).

Operational guidance:
- Use GSM/Vault for runtime secrets; never bake secrets into images.
- Use KMS (cloud provider) for envelope encryption of long-term artifacts (AMI signing, state files).
- Ensure Terraform runs are idempotent and use remote state with locking.

Follow-up issues were opened to track full implementations and tests: #1540, #1541, #1542.
