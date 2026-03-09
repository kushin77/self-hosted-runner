# Example: Provision KEDA

This example demonstrates using the `terraform/modules/keda` module to install KEDA and a Prometheus adapter into a Kubernetes cluster.

Run:

```bash
terraform init
terraform apply -auto-approve
```

Ensure your `kubeconfig` is available to the provider.
