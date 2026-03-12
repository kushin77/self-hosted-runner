CI upload instructions

This file explains how to enable the Cloud Build upload step for build logs.

1. Choose a logs source bucket where Cloud Build stores logs (example: `gs://projects/_/logs/your-cloudbuild-logs-bucket`).
2. Grant the Cloud Build service account (or `deployer-run@nexusshield-prod.iam.gserviceaccount.com` if appropriate) `roles/storage.objectViewer` on that bucket.

Example (bucket-level least-privilege):

```
BUCKET_NAME=projects/_/logs/your-cloudbuild-logs-bucket
gsutil iam ch serviceAccount:deployer-run@nexusshield-prod.iam.gserviceaccount.com:objectViewer gs://$BUCKET_NAME
```

3. Add `cloudbuild/cloudbuild-upload-logs.yaml` as a final step in your `cloudbuild.yaml`, or reference it via an include. Use substitutions to pass `_LOG_BUCKET` and `_BUILD_ID`:

```
# Example trigger substitution settings
_SUBSTITUTIONS:
  _LOG_BUCKET=gs://projects/_/logs/your-cloudbuild-logs-bucket
  _BUILD_ID=$BUILD_ID
```

4. Optionally set an archive target (the template uploads to `gs://nexusshield-dev-sbom-archive/build-logs/$BUILD_ID`). Ensure the uploader account has `storage.objects.create` on the archive bucket.

5. Test with a known `BUILD_ID` once IAM is configured.

If you prefer, provide the exact log bucket name and I will update the substitution defaults and open a small PR to wire this into Cloud Build triggers.