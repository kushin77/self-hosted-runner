Title: Audit & Sanitize repository docs and artifacts for token-like placeholders

Context:
- We previously redacted several example tokens; a broader audit is needed to locate remaining token-like literals across docs, workflows, and artifacts.

Goal:
- Produce a prioritized list of files requiring redaction and submit small PRs to replace literals with safe placeholders.

Actions:
1. Run a repository-wide search for patterns like `ghp_`, `GITHUB_TOKEN=`, `VAULT_`, `aws_secret_access_key`, and other typical token formats.
2. Verify matches are not false positives (e.g., scripts that expect placeholders).
3. Prepare small, focused PRs that only change docs/workflow files to placeholders.
4. Track progress by closing or updating this file with the list of PRs and file paths.

Notes:
- Avoid committing real secrets. If a real secret is discovered, rotate and remove it immediately following org procedures.
