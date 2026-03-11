# Secret Storage Examples

This file contains example commands for storing the verifier SSH private key and GitHub token in common secret stores.

Google Secret Manager (GSM) — SSH key
```sh
# create secret (if not exists) and add version
gcloud secrets create verifier-ssh-key --data-file=/tmp/verifier_key --replication-policy="automatic" --project=YOUR_PROJECT
# grant access to management service account
gcloud secrets add-iam-policy-binding verifier-ssh-key --member=serviceAccount:MANAGEMENT_SA@YOUR_PROJECT.iam.gserviceaccount.com --role=roles/secretmanager.secretAccessor --project=YOUR_PROJECT
```

Google Secret Manager (GSM) — GitHub token
```sh
printf "%s" "YOUR_GITHUB_TOKEN" >/tmp/verifier_ghtoken
gcloud secrets create verifier-github-token --data-file=/tmp/verifier_ghtoken --replication-policy="automatic" --project=YOUR_PROJECT
gcloud secrets add-iam-policy-binding verifier-github-token --member=serviceAccount:MANAGEMENT_SA@YOUR_PROJECT.iam.gserviceaccount.com --role=roles/secretmanager.secretAccessor --project=YOUR_PROJECT
```

HashiCorp Vault (KV) — SSH key
```sh
# assuming Vault CLI is authenticated and KV v2 mounted at secret/
vault kv put secret/verifier ssh_key=@/tmp/verifier_key
# grant appropriate Vault policies to the management principal
```

HashiCorp Vault (KV) — GitHub token
```sh
vault kv put secret/verifier github_token=YOUR_GITHUB_TOKEN
```

AWS KMS + S3 — encrypted private key (alternative)
```sh
aws kms encrypt --key-id alias/your-key --plaintext fileb:///tmp/verifier_key --output text --query CiphertextBlob > /tmp/verifier_key.enc
aws s3 cp /tmp/verifier_key.enc s3://your-secret-bucket/verifier/verifier_key.enc
# management host should have a role to decrypt via KMS and read from S3
```
