# Phase P4 Tracking & Implementation Status

## Issue #244: Strategic Roadmap — Advanced Managed-Homing & Global Multi-Cloud Expansion

### Completed & In-Flight

**Infrastructure & Scaffolds:**
- ✅ PR #1536: Roadmap, Terraform module scaffolds (Azure/AWS), runner bootstrap PoC, CI linting
- ✅ PR #1545: Vault PKI scaffold, Envoy mTLS PoC manifests
- ✅ PR #1550: Vault Agent sidecar + templates for cert rotation
- ✅ PR #1558: Envoy reload watcher sidecar + E2E smoke test

### Follow-Up Issues

**Security & Hardening:**
- #1540: Implement mTLS termination (in-flight)
- #1542: Integrate Vault/GSM/KMS for secret retrieval and rotation
- #1561: Secure Vault authentication (K8s auth, AppRole, Cloud IAM)
- #1563: Hardened Terraform state backends with KMS

**Operations & Testing:**
- #1541: Automate image rotation based on Trivy CVE detection
- #1551: Implement Envoy reload on cert refresh and cert rotation automation
- #1559: Add E2E tests to validate mTLS handshake and rotation

**Infrastructure & Provisioning:**
- #1562: Complete Vault PKI core setup and root/intermediate CA provisioning

### Objectives

By completing these issues, we will have:
- Immutable, idempotent Terraform-driven infra for Azure and AWS multi-cloud runners
- Managed-homing control-plane with mTLS and Vault-backed certificates
- Automated image rotation triggered by CVE detection (Trivy)
- AI-driven fleet management hooks (mock-oracle in place)
- Hands-off, fully-automated provisioning with no manual state mutations
- Secret management via Vault/GSM/KMS with automatic rotation and ephemeral credentials

### Next Steps

1. Merge PRs #1536, #1545, #1550, #1558 upon review.
2. Work follow-up issues in priority order:
   - #1559: E2E tests (foundation for validation)
   - #1561: Vault auth hardening (enables production use)
   - #1562: Vault PKI provisioning (core infrastructure)
   - #1541: Image rotation automation
   - #1563: Terraform state hardening (for ops)
3. Integrate all into a unified deployment pipeline and operator runbook.

---
Last updated: March 8, 2026
