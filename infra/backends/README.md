# Terraform Backend Configuration with KMS Encryption

## AWS S3 + DynamoDB Backend (with KMS)

```hcl
terraform {
  backend "s3" {
    bucket         = "YOUR_BUCKET_NAME"
    key            = "phase-p4/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
    kms_key_id     = "arn:aws:kms:us-east-1:ACCOUNT_ID:key/KEY_ID"
  }
}
```

## GCS Backend (with KMS via Google-managed keys)

```hcl
terraform {
  backend "gcs" {
    bucket = "YOUR_BUCKET_NAME"
    prefix = "phase-p4/terraform"
  }
}
```

Configure KMS via GCS bucket encryption settings or use application-level encryption.

## Implementation Steps

1. Create S3 bucket and DynamoDB table for locking.
2. Attach KMS key with appropriate key policy (see kms-key-policy.json).
3. Update backend configuration in root modules.
4. Run `terraform init` with `-backend-config` flag to migrate state.
5. CI should use `-backend-config` to inject backend settings securely (no state checked in).

## Security Notes

- Store KMS key ARN in a secure CI secret or SSM Parameter Store.
- Use least-privilege IAM roles for Terraform CI runners.
- Enable MFA delete on S3 bucket.
- Use S3 versioning to recover from accidental deletions.
