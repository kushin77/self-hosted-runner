# Managed-Homing (Control Plane) — Design Notes

Goal: Provide a centralized, secure API for runner registration across multiple VPCs (including air-gapped environments).

Key components:
- Registration API (OpenAPI spec placeholder)
- Agent bootstrap with mutual TLS or short-lived certs
- Ephemeral TTL logic based on job complexity and telemetry
- Image rotation trigger hooks (integrate with Trivy CVE feed)

Security considerations:
- Mutual TLS and mTLS pinning for registration
- Audit logging for registrations and rebalancing
- Least-privilege IAM roles for control-plane interactions

Next: Draft an OpenAPI spec and a minimal reference server (Go/Python) for PoC.
