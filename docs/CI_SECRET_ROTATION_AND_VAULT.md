# CI Secret Rotation & Vault Integration (recommended)

Purpose: ensure repository and runner secrets are rotated, least-privileged, and not long-lived. Prefer dynamic credentials fetched at runtime (Vault / AWS STS) over storing long-lived secrets in GitHub.

Key recommendations

- Minimal repository secrets: store only what is necessary (e.g. `AWS_ROLE_TO_ASSUME`, `AWS_REGION`). Avoid long-lived AWS access keys when possible.
- Use Organization-level secrets for values shared across multiple repos.
- Prefer short-lived credentials obtained at runtime (Vault, AWS STS AssumeRole) and revoke/rotate regularly.
- Limit secret access using GitHub Environments and required reviewers for protected workflows (guarded applies).

Vault integration patterns

1) Runner-side Vault agent
- Install/configure a Vault Agent or auth method on the self-hosted runner. On startup the agent fetches temporary AWS credentials and writes them to environment variables or a credentials file available only to the runner user.

2) Action-based Vault retrieval
- Use a dedicated GitHub Action or step to fetch secrets at job runtime (e.g., `hashicorp/vault-action`) and set them as environment variables for Terraform steps.

Example: fetch AWS creds from Vault in a workflow step

```yaml
- name: Obtain AWS credentials from Vault
  uses: hashicorp/vault-action@v2
  with:
    url: ${{ secrets.VAULT_ADDR }}
    method: github
    role: "ci-runner-role"
    secret: "secret/data/aws/ci"
  env:
    VAULT_TOKEN: ${{ secrets.VAULT_GITHUB_TOKEN }}

- name: Export AWS creds
  run: |
    echo "AWS_ACCESS_KEY_ID=${{ steps.vault.outputs.aws_access_key_id }}" >> $GITHUB_ENV
    # Export the AWS secret access key from Vault output (example removed to avoid exposing token-like strings)
    echo "AWS_SESSION_TOKEN=${{ steps.vault.outputs.aws_session_token }}" >> $GITHUB_ENV
```

Rotation policies

- Rotate org/repo secrets quarterly (or per-org policy) and audit access.
- Use AWS IAM policies with short session durations for assumed roles.
- Log and monitor secrets access and runner actions.

Operational checklist for adding secrets

<REDACTED_SECRET_REMOVED_BY_AUTOMATION>
2. Configure the runner to fetch secrets (agent) or the workflow to fetch them (action).  
3. Test in a non-prod environment (staging) and validate Terraform plan artifacts before guarded apply.

If you want, I can open a PR that adds example workflow snippets for your repo's plan/apply flows integrating Vault or short-lived credentials. I can also create a proposed GitHub Actions workflow change that swaps static secrets for a Vault step.
