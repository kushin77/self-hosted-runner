variable "kubeconfig_path" {
  type    = string
  default = "~/.kube/config"
}

provider "kubernetes" {
  config_path = pathexpand(var.kubeconfig_path)
}

module "keda" {
  source    = "../../modules/keda"
  namespace = "keda"
}
