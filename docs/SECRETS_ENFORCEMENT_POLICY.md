# Secrets Management: GSM/Vault/KMS Enforcement

**Effective date:** March 12, 2026  
**Status:** ENFORCED

## Policy

All credentials, API keys, and secrets **must** be managed via one of:
1. **Google Secret Manager (GSM)** — recommended for GCP projects
2. **HashiCorp Vault** — recommended for on-prem or multi-cloud
3. **AWS KMS** — recommended for AWS projects

**NO** plaintext secrets may be committed to the repository.

### Prohibited

- ❌ AWS access keys in `.env` files
- ❌ API tokens in `secrets.json`
- ❌ Private keys in `.github/secrets` or elsewhere
- ❌ Database passwords in `terraform.tfvars`
- ❌ GitHub tokens in CI config files
- ❌ Service account JSON keys in the repo

### Permitted

- ✅ GSM secret references: `projects/PROJECT_ID/secrets/SECRET_NAME/versions/latest`
- ✅ Vault paths: `secret/data/my-cred`
- ✅ KMS-encrypted values (never plaintext)
- ✅ Example/template files: `.env.example` (no real secrets)

## Implementation

### For Cloud Build (GCP):

```yaml
# cloudbuild.yaml
steps:
  - name: 'gcr.io/cloud-builders/gke-deploy'
    env:
      - 'CLOUDSDK_COMPUTE_ZONE=us-central1-a'
      - 'CLOUDSDK_CONTAINER_CLUSTER=my-cluster'
    secretEnv: ['DB_PASSWORD', 'API_TOKEN']
    args:
      - run
      - apply
      - '--input=k8s/'
secretsManagerConfigs:
  - versionName: projects/$PROJECT_ID/secrets/db-password/versions/latest
    env: 'DB_PASSWORD'
  - versionName: projects/$PROJECT_ID/secrets/api-token/versions/latest
    env: 'API_TOKEN'
```

### For Terraform:

```hcl
# terraform/main.tf
data "google_secret_manager_secret_version" "db_password" {
  secret      = "db-password"
  version     = "latest"
}

resource "kubernetes_secret" "app" {
  metadata {
    name      = "app-secrets"
    namespace = "default"
  }

  data = {
    DB_PASSWORD = data.google_secret_manager_secret_version.db_password.secret_data
  }
}
```

### For GitLab CI (via agent):

```yaml
# .gitlab-ci.yml
integration_test:
  stage: test
  script:
    - export DB_PASSWORD=$(gcloud secrets versions access latest --secret="db-password")
    - ./test.sh
  environment:
    kubernetes:
      kubeconfig_inline: $KUBE_CONFIG
```

## Audit & Compliance

- All secret accesses logged to Cloud Audit Logs.
- Secret rotation enforced with TTL policies.
- No secret value ever appears in logs (masked).
- Branch protection requires CODEOWNERS review for any secret changes.

## Credential Rotation

Rotate at least every **90 days**:

```bash
# Generate new secret version
echo -n "new-secret-value" | gcloud secrets versions add db-password --data-file=-

# Verify
gcloud secrets versions list db-password

# Update deployments (auto via Kubernetes refresh)
kubectl rollout restart deployment/myapp
```

## If you have a secret committed by accident:

1. **Immediately rotate the secret** (generate new value in GSM/Vault/KMS).
2. **Purge from git history** (see [#2779](https://github.com/kushin77/self-hosted-runner/issues/2779)):
   ```bash
   git filter-repo --path secrets.json --invert-paths
   git push --force-with-lease
   ```
3. **Audit affected systems** for any exposure.
4. **Report** in issue [#2779](https://github.com/kushin77/self-hosted-runner/issues/2779).

## References

- [Google Secret Manager](https://cloud.google.com/secret-manager/docs)
- [HashiCorp Vault](https://www.vaultproject.io/)
- [AWS KMS](https://docs.aws.amazon.com/kms/)
- [Issue #2779: Migrate secrets](https://github.com/kushin77/self-hosted-runner/issues/2779)
