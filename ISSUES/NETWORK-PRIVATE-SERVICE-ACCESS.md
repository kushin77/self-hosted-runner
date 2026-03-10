Title: Enable Private Service Access / VPC peering for Cloud SQL private IP

Description
- Terraform attempted to create Cloud SQL with private IP but failed due to org policy `sql.restrictPublicIp`.
- The deployment requires Private Service Access (PSA) and an allocated reserved IP range in the project VPC.

Required actions (urgent)
- Priority: **High** — required to complete production Cloud SQL private-IP creation.
- Assignee: `network-team` (or any admin with `roles/servicenetworking.serviceAgent` / project owner privileges)
- Network team to perform the following (or grant permissions for the terraform SA `nexusshield-deployer@<PROJECT>.iam.gserviceaccount.com` to perform them):
  1. Allocate a reserved range (example):

    gcloud compute addresses create google-managed-services-<PROJECT> --global --prefix-length=16 --addresses=10.64.0.0 --project=<PROJECT>

    (Or pick an available /16 in your allocation pool.)

  2. Create a Private Service Connection (PSA):

    gcloud services vpc-peerings connect --service=servicenetworking.googleapis.com --ranges=google-managed-services-<PROJECT> --network=projects/<PROJECT>/global/networks/<VPC_NAME> --project=<PROJECT>

  3. Ensure the `servicenetworking.googleapis.com` API is enabled in the project:

    gcloud services enable servicenetworking.googleapis.com --project=<PROJECT>

  4. Verify peering status and that the reserved range is associated:

    gcloud services vpc-peerings list --project=<PROJECT>
    gcloud compute addresses describe google-managed-services-<PROJECT> --global --project=<PROJECT>

Verification steps
- After PSA is set up, re-run `nexusshield/infrastructure/terraform/production` apply.
- Confirm Cloud SQL instance shows `Private IP` and Cloud Run can connect over VPC connector (if configured).

Notes
- If org policy cannot be changed, request a managed DB offering or alternative DB plan.
- Contact: network-team (cc:security)
