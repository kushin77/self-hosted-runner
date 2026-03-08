// Example root module using infra/aws/spot module

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

module "runners_spot" {
  source = "../../aws/spot"
  name   = "example-runners"
  ami_id = var.ami_id
}

// NOTE: Replace `ami_id` with a real AMI built via image pipeline.
