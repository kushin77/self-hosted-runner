GitOps & Vault Integration Guide
================================

Purpose
-------
Document recommended patterns for combining GitOps controllers (ArgoCD/Flux) with Vault-based secret management in a sovereign, air-gapped environment.

Principles
----------
- Do not store plaintext secrets in Git. Use one of the following patterns:
  - Sealed Secrets (sops/age/GPG) for encrypted secrets stored in Git
  - ExternalSecrets/Vault CSI or Vault-Injector to fetch secrets at runtime
  - Git-locked secret bundles stored in MinIO and referenced by manifests
- Prefers short-lived, audited credentials (Vault tokens/approle with narrow scope).
- Keep secret provision and rotation outside of GitOps reconciliation; GitOps should reference stable, declarative secret references.

Recommended Patterns
--------------------
1. Vault + ExternalSecrets
   - Deploy ExternalSecrets operator in the cluster.
   - Configure ExternalSecrets to authenticate to Vault (Kubernetes auth role, or Vault Agent).
   - Store secret references in Git (no raw secret values). ExternalSecrets will fetch and create Kubernetes Secrets at runtime.

2. Vault Agent Injector (Kubernetes)
   - Use Vault Agent Injector to inject secrets directly into pods via projected volumes.
   - Advantage: no Kubernetes Secret storage, secrets only mounted in-memory in running pods.

3. Sealed Secrets / Sops
   - Use Sops (with age/GPG) or SealedSecrets to store encrypted secret manifests in Git.
   - Keep the private keys in Vault-controlled HSM or KMS.

Bootstrapping
-------------
- Avoid embedding Vault root tokens in automation. Use AppRole or OIDC for CI and runners.
- Use `ci/scripts/vault-approle-login.sh` for CI runner login to obtain a short-lived Vault token.
- For cluster controllers, use Kubernetes auth with bound service accounts or Vault Agent as an init sidecar.

Security Notes
--------------
- Ensure TLS and CA pinning for Vault endpoints in runner images.
- Audit all Vault access and enable detailed audit logging to MinIO or centralized archive.
- Regularly rotate AppRole secret_ids and limit their TTLs.
