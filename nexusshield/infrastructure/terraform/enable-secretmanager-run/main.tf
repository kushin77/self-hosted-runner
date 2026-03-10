variable "project" {
  type = string
}

provider "google" {
  project = var.project
}

module "enable_secretmanager" {
  source  = "../modules/enable-secretmanager"
  project = var.project
}
