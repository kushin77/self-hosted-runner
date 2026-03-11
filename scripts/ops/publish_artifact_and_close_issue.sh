#!/usr/bin/env bash
set -euo pipefail

# Usage: export S3_BUCKET, GITHUB_TOKEN, OWNER, REPO, ISSUE_NUMBER then run this script
ARTIFACT_FILE="/home/akushnir/self-hosted-runner/canonical_secrets_artifacts_1773253164.tar.gz"
SHA256="878fd9a490d2ae18c06ac5c80367683a72271093599498f86d806c761b597719"
BRANCH="canonical-secrets-impl-1773247600"
RECORD_FILE="/home/akushnir/self-hosted-runner/DEPLOYMENT_ARTIFACTS_RECORD.md"

: "${S3_BUCKET:?S3_BUCKET must be set}
: "${GITHUB_TOKEN:?GITHUB_TOKEN must be set}
: "${OWNER:?OWNER must be set}
: "${REPO:?REPO must be set}
: "${ISSUE_NUMBER:?ISSUE_NUMBER must be set}

OBJECT_KEY="$(basename "$ARTIFACT_FILE")"
S3_URI="s3://$S3_BUCKET/$OBJECT_KEY"

echo "Starting publish: $ARTIFACT_FILE -> $S3_URI"

if ! command -v aws >/dev/null 2>&1; then
  echo "aws CLI not found; aborting" >&2
  exit 2
fi

# Check artifact exists
if [ ! -f "$ARTIFACT_FILE" ]; then
  echo "Artifact not found at $ARTIFACT_FILE" >&2
  exit 2
fi

# Upload only if not present
if aws s3 ls "$S3_URI" >/dev/null 2>&1; then
  echo "Artifact already exists in S3: $S3_URI (skipping upload)"
else
  echo "Uploading artifact to S3..."
  aws s3 cp "$ARTIFACT_FILE" "$S3_URI"
fi

# Generate presigned URL (7 days)
PRESIGNED_URL=$(aws s3 presign "$S3_URI" --expires-in 604800)
if [ -z "$PRESIGNED_URL" ]; then
  echo "Failed to generate presigned URL" >&2
  exit 3
fi

echo "Presigned URL: $PRESIGNED_URL"

# Update record file atomically
TMP_RECORD=$(mktemp)
awk -v url="$PRESIGNED_URL" -v sha="$SHA256" -v s3uri="$S3_URI" '
BEGIN{updated=0}
{print}
END{
 if(updated==0) exit 0
}
' "$RECORD_FILE" > "$TMP_RECORD" || true

# If record already contains Published URL, replace or append
if grep -q "Presigned URL:" "$RECORD_FILE" >/dev/null 2>&1; then
  sed -e "s|^Presigned URL:.*$|Presigned URL: $PRESIGNED_URL|" -e "s|^S3 URI:.*$|S3 URI: $S3_URI|" "$RECORD_FILE" > "$TMP_RECORD"
else
  cat "$RECORD_FILE" > "$TMP_RECORD"
  {
    echo "";
    echo "Published: true";
    echo "S3 URI: $S3_URI";
    echo "Presigned URL: $PRESIGNED_URL";
  } >> "$TMP_RECORD"
fi

mv "$TMP_RECORD" "$RECORD_FILE"

# Commit & push update to branch
pushd /home/akushnir/self-hosted-runner >/dev/null
git checkout -q $BRANCH || true
git add "$RECORD_FILE"
git commit -m "chore: publish artifact and record presigned URL" || echo "No changes to commit"
git push origin $BRANCH || echo "git push failed; continuing"
popd >/dev/null

# Post comment to GitHub and close issue
COMMENT_BODY="Deployment completed and artifact published.\n\nArtifact: $S3_URI\nPresigned URL (7 days): $PRESIGNED_URL\nSHA256: $SHA256\nBranch: $BRANCH\n\nValidation: see repo branch $BRANCH for verification artifacts and logs."

echo "Posting comment to https://api.github.com/repos/$OWNER/$REPO/issues/$ISSUE_NUMBER/comments"

curl -s -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \
  -d "{\"body\": \"$COMMENT_BODY\"}" \
  "https://api.github.com/repos/$OWNER/$REPO/issues/$ISSUE_NUMBER/comments" | jq -r '.html_url // empty' || true

# Close the issue
curl -s -X PATCH -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \
  -d '{"state":"closed"}' "https://api.github.com/repos/$OWNER/$REPO/issues/$ISSUE_NUMBER" >/dev/null || true

echo "Publish + issue update completed."
