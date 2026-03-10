# Infrastructure Remediation Steps (Terraform)

Date: 2026-03-10

This document lists the minimal, safe remediation actions required to resolve the Terraform failures observed during finalization. Perform these steps in the `nexusshield-prod` project and re-run `terraform apply` afterwards.

## 1) VPC Connector ID must be RFC-compliant

Error seen:
```
Connector ID must follow the pattern ^[a-z][-a-z0-9]{0,23}[a-z0-9]$
```

Action:
- Edit `terraform/main.tf` (or the connector resource file) and set the connector name to a lowercase, alphanumeric/hyphen string that:
  - Starts with a lowercase letter
  - Contains only lowercase letters, digits and hyphens
  - Is between 1 and 24 characters long
  - Ends with a lowercase letter or digit

Recommended name: `production-portal-connector`

Example Terraform resource change (patch):
```hcl
resource "google_vpc_access_connector" "cloud_run" {
  name    = "production-portal-connector"
  region  = var.region
  project = var.gcp_project
  min_instances = 2
  max_instances = 3
  network = var.network
}
```

Why: Cloud Run VPC connector enforces a strict resource id pattern. Choosing a short, descriptive name avoids replacements.

---

## 2) Cloud SQL Private IP requires a Private Services Connection

Error seen:
```
failed to create instance because the network doesn't have at least 1 private services connection
```

Action (operator / GCP admin):
1. Choose an unused IP range (CIDR) in your VPC for Google-managed services, e.g. `10.64.0.0/16`. Verify it does not overlap existing ranges.

2. Reserve an address range (global) for VPC peering:
```bash
gcloud compute addresses create google-managed-services-prod-portal --global \
  --purpose=VPC_PEERING --addresses=10.64.0.0 --prefix-length=16 --project=nexusshield-prod
```

3. Create the VPC peering connection to the `servicenetworking` API:
```bash
gcloud services vpc-peerings connect --service=servicenetworking.googleapis.com \
  --network=production-portal-vpc --ranges=google-managed-services-prod-portal --project=nexusshield-prod
```

4. Verify the connection:
```bash
gcloud services vpc-peerings list --project=nexusshield-prod
```

5. Re-run Terraform apply:
```bash
TF_VAR_environment=production TF_VAR_gcp_project=nexusshield-prod terraform -chdir=terraform apply -auto-approve
```

Notes:
- The reserved range must be global and not used by other peering ranges.
- If you use an IP range outside `10.0.0.0/8`, ensure it fits your organization's CIDR plan.

---

## 3) Optional: Vault & GSM Finalization

- Once Terraform completes, re-run the provisioning script to store `OPERATOR_SSH_KEY` in GSM:
```bash
bash scripts/deployment/provision-operator-credentials.sh --no-deploy --verbose
```

- If GSM IAM is still restricted, provide a service-account JSON with `roles/secretmanager.secretAdmin` and place it at `~/.credentials/service-account.json` before re-running the provisioning script.

---

## 4) Validation & Rollback

- After apply, run the comprehensive validation:
```bash
bash scripts/validation/comprehensive-validation.sh
```

- If anything fails, revert the Terraform changes and open an incident.

---

If you want, I can open a PR with the connector rename change (`production-portal-connector`) for review. Otherwise, run the above operator commands and I will re-run Terraform automatically.
