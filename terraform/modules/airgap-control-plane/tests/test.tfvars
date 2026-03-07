# Test configuration for airgap-control-plane Terraform module
# These values are used when running Terraform tests

# Use default provider configuration from kubeconfig
# The Kubernetes provider will use the current context

# Registry authentication (for testing with auth enabled)
# In real deployment, use AWS Secrets Manager, HashiCorp Vault, or similar
registry_username = "admin"
registry_password = "test-password" # Should use a secrets manager in production

# Test image sizes (smaller than production for faster testing)
image_storage_size = "10Gi"
