GitHub Issue Creation (helper)

This repo includes `scripts/create_github_issues.sh` which uses the GitHub CLI (`gh`) to create the infra/workflow/test issues we need.

Usage:

```bash
# Ensure you are authenticated with gh
gh auth login

# Make script executable and run
chmod +x scripts/create_github_issues.sh
./scripts/create_github_issues.sh
```

Notes:
- The script assumes the repository `akushnir/self-hosted-runner`. Edit the script to change the repo if needed.
- If you prefer a direct API approach, set `GITHUB_TOKEN` with appropriate scopes (`repo`) and use the GH REST API or modify the script accordingly.
