History purge plan — automated remediation (draft)

Purpose
-------
This is a reviewed, idempotent plan to remove sensitive blobs from git history using `git filter-repo`.

Summary
-------
- We identified potential leaked tokens in repository history (see issue #1111 and gists).
- This plan prepares a safe script and clear operator steps to run `git filter-repo` and rotate secrets.

Safety & approvals
------------------
- This is a destructive operation (rewrites history). Do NOT run without coordination: close active PRs, notify integrators, and plan a force-push window.
- The script is provided for maintainers to review. Once approved, run from a maintenance branch/host with a fresh clone and follow the checklist below.

Checklist (operator)
--------------------
1. Communicate planned force-push window to all contributors.
2. Ensure you have a fresh local clone and the `git` remote is reachable.
3. Ensure `git-filter-repo` is installed: `pip install git-filter-repo`.
4. Run the included `prepare-filter-repo.sh --dry-run` to see which refs/objects will be removed.
5. If dry-run looks correct, run `prepare-filter-repo.sh` to rewrite history locally.
6. Push rewritten branches with `git push --all --force` and `git push --tags --force`.
7. Rotate any exposed secrets (GitHub PATs, deploy keys) immediately after the push.
8. Update issue #1111 with the outcome and links to rotated secrets rotation logs.

Files
-----
- `prepare-filter-repo.sh` — idempotent helper to run `git filter-repo` with common patterns (dry-run supported).

If you want me to proceed and execute this plan (I will coordinate push and rotation), reply with: "approve history purge".
