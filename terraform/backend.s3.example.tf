terraform {
  backend "s3" {
    bucket         = "<your-tf-state-bucket>"
    key            = "runners/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}

# Notes:
# - Copy this file into your real terraform directory as a secure backend configuration
#   (do NOT commit sensitive production values). Use CI/CD secrets or a secure vault
#   to supply values when running in automation.
