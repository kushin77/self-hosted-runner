Title: Enable Private Service Access / VPC peering for Cloud SQL private IP

Description
- Terraform attempted to create Cloud SQL with private IP but failed due to org policy `sql.restrictPublicIp`.
- The deployment requires Private Service Access (PSA) and an allocated reserved IP range in the project VPC.

Required actions
- Network team to perform the following (or grant permissions for terraform SA to):
  1. Allocate a reserved range: `gcloud compute addresses create google-managed-services-<PROJECT> --global --addresses=<CIDR>` or via console.
  2. Create a Private Service Connection: `gcloud services vpc-peerings connect --service=servicenetworking.googleapis.com --ranges=google-managed-services-<PROJECT> --network=projects/<PROJECT>/global/networks/<VPC_NAME> --project=<PROJECT>`
  3. Verify `servicenetworking.googleapis.com` is enabled for the project.

Verification steps
- After PSA is set up, re-run `nexusshield/infrastructure/terraform/production` apply.
- Confirm Cloud SQL instance shows `Private IP` and Cloud Run can connect over VPC connector (if configured).

Notes
- If org policy cannot be changed, request a managed DB offering or alternative DB plan.
- Contact: network-team (cc:security)
