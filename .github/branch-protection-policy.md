# Branch Protection Policy

## Main Branch

Enforce the following on the `main` branch:

### Status Checks
- [x] Require branches to be up to date before merging
- [x] Status checks must pass:
  - Cloud Build (ci/cloud-build)
  - Pre-commit hooks (security/secrets-scan)

### Reviews
- [x] Require 1 approving review before merge
- [x] Dismiss stale pull request approvals when new commits are pushed
- [x] Require code owner reviews (if CODEOWNERS file exists)

### Restrictions
- [x] Allow force pushes: NO
- [x] Allow deletions: NO
- [x] Allow auto-merge: YES (squash only)

### Admins
- [x] Enforce above restrictions for administrators too

## Implementation

### Terraform (Preferred)
```hcl
resource "github_branch_protection" "main" {
  repository_id = github_repository.repo.id
  pattern       = "main"
  
  required_status_checks {
    strict   = true
    contexts = ["Cloud Build", "security/secrets-scan"]
  }
  
  require_code_owner_reviews = true
  enforces_admins            = true
  require_branches_up_to_date = true
  allow_force_pushes         = false
  allow_deletions            = false
}
```

### GitHub API
```bash
gh api repos/$OWNER/$REPO/branches/main/protection \
  --input branch-protection.json
```

### Not via GitHub UI (Policy Enforcement)
All branch protection must be automated via Terraform or API.
Manual UI changes are logged and audited.
