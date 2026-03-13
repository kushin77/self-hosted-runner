variable "github_token_owner" {
  description = "The GitHub owner/org for the repository (used by Github provider)."
  type        = string
  default     = ""
}

variable "github_token_repo" {
  description = "The GitHub repository name for branch protection."
  type        = string
  default     = ""
}

variable "cloud_build_status_contexts" {
  description = "List of status check contexts to require (Cloud Build)."
  type        = list(string)
  default     = ["cloudbuild"]
}
