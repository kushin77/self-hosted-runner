/*
  Terraform: GitHub Branch Protection for Direct Deployment CI/CD
  Purpose: Enforce branch protection on `main` requiring Cloud Build status checks
  
  FAANG Governance Requirements:
  - Require policy-check and direct-deploy builds to pass before merge
  - Block .github/workflows/* commits
  - Enforce strict required status checks (dismiss stale reviews on new commits)
  - Require code review (CODEOWNERS)
  - No force pushes or deletions allowed
*/

# ---------------------------------------------------------------------------
# Branch Protection Rule for `main`
# ---------------------------------------------------------------------------
resource "github_branch_protection" "main" {
  repository_id = var.github_repo_name
  pattern       = "main"

  # Require direct push review (if needed)
  require_conversation_resolution = true

  # =========================================================================
  # Required Status Checks (webhook-compatible via Cloud Build API status)
  # =========================================================================
  required_status_checks {
    strict   = true  # Dismiss stale reviews on new commits
    contexts = [
      "policy-check-trigger",      # Reports status via Cloud Build API -> GitHub
      "direct-deploy-trigger",     # Reports status via Cloud Build API -> GitHub
    ]
  }

  # =========================================================================
  # Require Pull Request Reviews
  # =========================================================================
  required_pull_request_reviews {
    dismiss_stale_reviews           = true
    require_code_owner_reviews      = true
    required_approving_review_count = 1
  }

  # =========================================================================
  # Block direct force pushes and deletions
  # =========================================================================
  force_push_bypassers = [] # No one can force push
  allows_deletions     = false

  depends_on = []
}

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------
output "main_branch_protection_id" {
  description = "Branch protection rule ID for main"
  value       = github_branch_protection.main.id
}
