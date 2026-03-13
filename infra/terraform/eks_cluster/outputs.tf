output "kubeconfig" {
  value = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = module.eks.cluster_certificate_authority_data
    name                   = module.eks.cluster_id
  }
}
