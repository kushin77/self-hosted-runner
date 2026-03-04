## Proposed cleanup: Non-organization GitHub Actions runners

Date: 2026-03-04

Summary
- Repository has repository-scoped self-hosted runners that should be removed and replaced by organization runners to centralize management and ensure high-availability.

Detected repo runners (candidates for cleanup):
- dev-elevatediq-runner (id: 24) — labels: self-hosted, Linux, X64, gpu
- dev-elevatediq-runner-hardened (id: 25) — labels: self-hosted, Linux, X64

Recommended actions
1. Verify these runners are not required by any external repos or jobs running outside org-runner pool.
2. Migrate any workflows that require special labels (gpu, dev-elevatediq-2) to explicit runner groups in the org runners or add matching labels to org runners.
3. Remove repository runners using GitHub API / `gh` CLI:

   gh api -X DELETE /repos/:owner/:repo/actions/runners/24
   gh api -X DELETE /repos/:owner/:repo/actions/runners/25

4. Monitor GitHub Actions runs for failures for 24h after removal and revert if needed.

Notes
- A script has been added: `scripts/pmo/list-non-org-runners.sh` to enumerate repo vs org runners.
- A migration helper: `scripts/pmo/migrate-workflows-to-org-runner.sh` was added and backups of workflows saved in `.backups/workflows`.

If you want me to create a GitHub issue for this, I will attempt to use `gh issue create` next. If `gh` is not authenticated, the above file will serve as the tracked proposal.
