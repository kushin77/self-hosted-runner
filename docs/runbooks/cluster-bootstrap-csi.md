Cluster bootstrap — Secrets Store CSI Driver + Providers

Purpose: steps for operators to install the Secrets Store CSI driver and configure providers (Vault and Google Secret Manager) in an idempotent, automated way.

Prereqs:
- kubeconfig with admin access
- `helm` and `kubectl` available
- IAM/IRSA roles prepared for provider service accounts (see infra/terraform/eks_cluster for guidance)

Automated install (operator):

```sh
# from repo root
export AWS_PROFILE=dev # if needed for IRSA tooling
./scripts/automation/install_csi_and_providers.sh kube-system
```

After install:
- Apply the appropriate `SecretProviderClass` in `k8s/secretproviderclasses/`.
- Patch the `ServiceAccount` used by the CronJob (in `k8s/milestone-organizer-cronjob.yaml`) to ensure it uses the IRSA role that grants access to Vault/GSM.
- Update the CronJob manifest to add a CSI volume:
  - name: `secrets-store` mountPath: `/var/run/secrets/gh` and use `secretProviderClass: spc-gsm-gh-token` or `spc-vault-gh-token`.

Validation:
- Create a job from CronJob and exec into pod to verify `/var/run/secrets/gh/gh_token` exists and contains the token.
- Verify pod can access S3 (if uploading artifacts) via `aws sts get-caller-identity`.

Security note:
- Do not commit raw tokens to git. SecretProviderClass references cloud secrets by resource name only.
