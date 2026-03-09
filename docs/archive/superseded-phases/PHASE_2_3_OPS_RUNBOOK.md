# Operational Runbook: Phase 2/3 Infrastructure Apply

This runbook guides the operations team through the manual application of the Terraform state for production infrastructure.

## Prerequisites:
- GCP Service Account JSON key (for administrative roles).
- `terraform.tfvars` populated with production values.

## Steps:
1. **Initialize Terraform**:
   ```bash
   cd terraform
   terraform init
   ```

2. **Validate State**:
   ```bash
   terraform plan -var-file=terraform.tfvars -out=prod.plan
   ```

3. **Apply Changes**:
   ```bash
   terraform apply prod.plan
   ```

## Post-Apply Verification:
- Verify Vault unseal via the logs: `kubectl logs -l app.kubernetes.io/name=vault`
- Confirm GCS bucket access.
