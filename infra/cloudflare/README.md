Cloudflare API Token (GSM)

This secret stores the Cloudflare API token used for DNS, firewall, and CDN operations.

Secret name: `cloudflare-api-token` (project: `nexusshield-prod`)

Current state: placeholder version added. Replace with the real token using the command below.

Replace with real token:

```bash
echo -n "<REAL_TOKEN>" | gcloud secrets versions add cloudflare-api-token --project=nexusshield-prod --data-file=-
```

Verify:

```bash
gcloud secrets versions access latest --secret=cloudflare-api-token --project=nexusshield-prod
```

Operator note: Do NOT paste tokens into chat. Use the `gcloud` command above to add the secret. After adding, update any services that consume the token (e.g., Terraform, Cloud Build substitutions) to use `projects/nexusshield-prod/secrets/cloudflare-api-token:latest`.
