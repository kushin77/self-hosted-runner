Contributor Recovery After History Rewrite

If you have local branches or unpublished work, follow these safe steps to recover after the repository history was rewritten and force‑pushed.

Recommended (clean, simplest):
1. Backup any local uncommitted changes:

```bash
git status --porcelain
# If you have local changes, create a patch or temporary branch
git add -A
git commit -m "WIP: save local changes before history rewrite" || true
git format-patch -o /tmp/my-patches origin/main..HEAD
# Or stash:
# git stash push -m "WIP before history rewrite"
```

2. Re-clone the repository (recommended to avoid surprises):

```bash
cd ~
mv ~/my-repo ~/my-repo.old-$(date +%s)
git clone git@github.com:kushin77/self-hosted-runner.git
cd self-hosted-runner
```

3. Re-apply your saved commits or patches:

```bash
# If you made patches:
git am /tmp/my-patches/*.patch
# If you stashed:
# git stash pop
```

Alternate (try to update in-place):
1. Fetch & reset to the new origin state (destructive locally):

```bash
git fetch origin --prune
# create a local backup branch first
git branch backup-before-rewrite-$(date +%s)
# reset your local main to origin/main
git checkout main
git reset --hard origin/main
```

2. Rebase or cherry-pick your feature branches onto the new main:

```bash
git checkout your-feature
git rebase --onto origin/main <old-base> your-feature
# or
git cherry-pick <commit>
```

Notes & Troubleshooting
- If you see duplicate commit errors during rebase, abort and re-evaluate which commits need to be cherry-picked.
- If you used forks or remotes, ensure you update remotes to point to the cleaned origin.
- Contact the repository maintainers if you encounter conflicts you cannot resolve.

If you'd like, I can create a small script to automate the "backup->reclone->apply patches" flow and open a PR with it. Please confirm and I'll proceed.
