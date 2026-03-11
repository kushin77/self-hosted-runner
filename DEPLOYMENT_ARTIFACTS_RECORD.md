Deployment artifact record

- Artifact: canonical_secrets_artifacts_1773253164.tar.gz
- Local path: /home/akushnir/self-hosted-runner/canonical_secrets_artifacts_1773253164.tar.gz
- Size: 9.5K
- SHA256: 878fd9a490d2ae18c06ac5c80367683a72271093599498f86d806c761b597719
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
# export GITHUB_TOKEN beforehand
PAYLOAD=$(jq -n --arg body "Deployment completed. Artifact uploaded: <INSERT_URL_OR_S3_PATH>. SHA256: 878fd9a490d2ae18c06ac5c80367683a72271093599498f86d806c761b597719\n\nValidation: see attached reports in repo and /tmp on runner." '{body: $body, state: "closed"}')
# Post comment
curl -s -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \
  -d '{"body":"Deployment completed. Artifact: <INSERT_URL>. SHA256: 878fd9a490d2ae18c06ac5c80367683a72271093599498f86d806c761b597719"}' \
  "https://api.github.com/repos/OWNER/REPO/issues/ISSUE_NUMBER/comments"
# Close issue
curl -s -X PATCH -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \
  -d '{"state":"closed"}' "https://api.github.com/repos/OWNER/REPO/issues/ISSUE_NUMBER"
```

3) After uploading, update this file with the public URL or presigned URL and push the change.

Notes:
- This runner currently has `aws` CLI installed but no configured credentials; set the AWS environment or IAM role before running the upload.
- The repository branch for deployment changes is `canonical-secrets-impl-1773247600`.
