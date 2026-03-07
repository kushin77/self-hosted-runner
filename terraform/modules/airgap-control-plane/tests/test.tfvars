# Test configuration for airgap-control-plane Terraform module
# These values are used when running Terraform tests

# Use default provider configuration from kubeconfig
# The Kubernetes provider will use the current context

# Test image sizes (smaller than production for faster testing)
# test.tf sets module-level image_storage_size; no root-level tfvars required
