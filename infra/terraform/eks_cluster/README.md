Usage:

1. Set variables in a `terraform.tfvars` or pass via CLI.
2. This module will create a VPC by default for unattended runs. To use an existing VPC, set `vpc_id` and `subnet_ids`.
3. Run `terraform init && terraform apply`.

Outputs:
- `kubeconfig` map with `host`, `cluster_ca_certificate`, and `name` to construct a kubeconfig for `kubectl`.

Notes:
- This module requires IAM permissions to create EKS, EC2, IAM roles, and CloudFormation resources.
- For IRSA and CSI integration, additional IAM policies and OIDC provider creation will be required after cluster creation.
