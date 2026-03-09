Self-contained history purge bundle

Usage

- Run this bundle on a stable machine with network access and an account that can force-push the repository.
- Example (dry-run, does not push):

  REPO_URL=https://github.com/owner/repo.git ./run_purge_bundle.sh

- To perform the actual push after validating results locally, set `DO_PUSH=1`:

  REPO_URL=https://github.com/owner/repo.git DO_PUSH=1 ./run_purge_bundle.sh

Files

- `run_purge_bundle.sh`: wrapper that downloads a standalone `git-filter-repo` script and runs it against a mirror clone.
- `replace.txt`: replacement rules for `--replace-text`. Edit carefully to match only confirmed secrets.

Notes

- This bundle is designed so maintainers can run it off-runner where environment restrictions (PEP 668) won't block installs.
- Always validate results locally before enabling `DO_PUSH=1`.
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
- This is a destructive operation (rewrites history). Do NOT run without coordination: close active Draft issues, notify integrators, and plan a force-push window.
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
