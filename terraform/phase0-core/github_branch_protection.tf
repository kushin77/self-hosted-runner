provider "github" {
  # Configure with a GitHub token that has admin:org and repo scope when applying.
}

variable "github_owner" {
  type = string
}

variable "github_repo" {
  type = string
}

variable "github_branch" {
  type    = string
  default = "main"
}

variable "cloud_build_status_contexts" {
  description = "List of required status check contexts provided by Cloud Build (exact names)."
  type        = list(string)
  default     = ["cloudbuild"]
}

resource "github_branch_protection" "main" {
  repository = var.github_repo
  pattern    = var.github_branch

  required_status_checks {
    strict   = true
    contexts = var.cloud_build_status_contexts
  }

  enforce_admins = true

  required_pull_request_reviews {
    dismiss_stale_reviews          = true
    require_code_owner_reviews     = false
    required_approving_review_count = 1
  }

  restrictions = {}
}
