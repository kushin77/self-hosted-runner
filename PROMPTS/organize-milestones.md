Organize Milestones

Purpose
- Provide a reusable assistant prompt to organize GitHub issues into milestones, create missing milestones, and assign issues using configurable heuristics and safe checks.

Use
- Replace placeholders (`OWNER/REPO`, `GITHUB_TOKEN` if needed) before running.

Prompt
-------
You are an automation assistant with GitHub permissions for the repository OWNER/REPO.

Task: Organize open issues into a small set of milestones (5-12). Do the following steps and explain actions taken:

1. Discover state
  - List all open issues (number, title, body, labels, current milestone).
  - Count how many issues already have milestones.

2. Propose milestones
  - Suggest 5–12 milestone names and short descriptions based on issue themes.
  - Group issues by likely milestone using keywords and labels; provide a preview (top 30 per group).

3. Create and assign (automatable)
  - Create any missing milestone on GitHub, using the GitHub API or `gh` CLI.
  - Assign issues to milestones in safe batches (e.g. 50 issues per batch) with retry/backoff.
  - If any issue is ambiguous, place it in a catch-all milestone named `All Untriaged`.

Rules and constraints
  - Do not close or edit issue titles/bodies.
  - Use idempotent operations: check existence before creating milestones.
  - Rate-limit API calls; use short sleeps and retries on 5xx or rate-limit responses.
  - Log all changes with issue number → milestone mapping and timestamp.

Parameters (examples)
  - repo: `kushin77/self-hosted-runner`
  - milestones: optional list to prefer/create
  - mapping: keyword->milestone overrides
  - batch_size: 50

Example `gh` CLI snippets
  - List open issues: `gh issue list --state open --limit 500 --json number,title,body,labels,milestone`
  - Create milestone: `gh api repos/OWNER/REPO/milestones -f title="Triage" -f description="..."`
  - Assign issue: `gh issue edit 123 --milestone "Triage"`

Output
  - A short summary of milestones created, number of issues assigned per milestone, any failures, and a link to a CSV or JSON mapping file if requested.

Safety notes
  - If you lack permission to create or edit milestones, produce the proposed mapping and the exact CLI/API commands to run instead.

End
