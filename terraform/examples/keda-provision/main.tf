provider "kubernetes" {}

module "keda" {
  source = "../../modules/keda"
  namespace = "keda"
}
