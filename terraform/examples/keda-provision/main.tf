variable "kubeconfig_path" {
  type    = string
  default = "~/.kube/config"
}

provider "kubernetes" {
  config_path = pathexpand(var.kubeconfig_path)
}

provider "helm" {}

module "keda" {
  source    = "../../modules/keda"
  namespace = "keda"
  providers = {
    kubernetes = kubernetes
    helm       = helm
  }
}
