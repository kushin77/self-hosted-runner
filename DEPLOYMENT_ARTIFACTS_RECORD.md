Deployment artifact record

- Artifact: canonical_secrets_artifacts_1773253164.tar.gz
- Local path: /home/akushnir/self-hosted-runner/canonical_secrets_artifacts_1773253164.tar.gz
- Size: 9.5K
-- SHA256 (truncated): 878fd9a4...7719
- Created: 2026-03-11

Manual upload & posting instructions

1) Upload to S3 (replace S3_BUCKET and optionally set AWS_PROFILE or export AWS credentials):

```bash
aws s3 cp /home/akushnir/self-hosted-runner/canonical_secrets_artifacts_1773253164.tar.gz s3://$S3_BUCKET/canonical_secrets_artifacts_1773253164.tar.gz
# optionally create presigned URL
aws s3 presign s3://$S3_BUCKET/canonical_secrets_artifacts_1773253164.tar.gz --expires-in 604800
```

2) Post verification comment to GitHub issue and close it (replace OWNER, REPO, ISSUE_NUMBER):

```bash
# To post the comment and close the issue: export a GitHub personal access token into your shell
# (operator step). Then use the GitHub API to POST a comment and PATCH the issue state.
# Example (operator-run):
# 1) Create JSON body with your message using `jq` or a small script.
# 2) POST to `https://api.github.com/repos/OWNER/REPO/issues/ISSUE_NUMBER/comments` with
#    an `Authorization` header containing your token.
# 3) PATCH the issue to `{"state":"closed"}` to close it.

Example operator commands (replace OWNER/REPO/ISSUE_NUMBER and provide a token in your
environment as appropriate):

```bash
# export a GitHub token in your operator shell (do not commit the token to git)
# export GH_TOKEN="<paste-token-here>"
# curl -H "Authorization: token $GH_TOKEN" -d '{"body":"Deployment completed..."}' \
#   "https://api.github.com/repos/OWNER/REPO/issues/ISSUE_NUMBER/comments"
# curl -X PATCH -H "Authorization: token $GH_TOKEN" -d '{"state":"closed"}' \
#   "https://api.github.com/repos/OWNER/REPO/issues/ISSUE_NUMBER"
```
```

3) After uploading, update this file with the public URL or presigned URL and push the change.

Notes:
- This runner currently has `aws` CLI installed but no configured credentials; set the AWS environment or IAM role before running the upload.
- The repository branch for deployment changes is `canonical-secrets-impl-1773247600`.
Repository Path: canonical_secrets_artifacts_1773253164.tar.gz
Committed repository copy of artifact for immutability and traceability.
