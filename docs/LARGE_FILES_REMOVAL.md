This repository currently contains large binary files that exceed GitHub's push limits.

Detected files (examples):
- actions-runner-1772733156/externals/node20_alpine/bin/node
- actions-runner-1772733156/externals/node20/bin/node
- actions-runner-1772733156/externals/node24_alpine/bin/node
- actions-runner-1772733156/externals/node24/bin/node

Recommended remediation steps (choose one):

Option A — Use Git LFS
1. Install Git LFS locally: `git lfs install`.
2. Track the binaries: `git lfs track "actions-runner-*/externals/**/bin/node"` and commit `.gitattributes`.
3. Migrate existing large files into LFS: `git lfs migrate import --include="actions-runner-*/externals/**/bin/node"`.
4. Force-push the rewritten history: `git push --force origin main` (coordinate with team).

Option B — Remove binaries from history (clean branch + upload to external storage)
1. Create a cleanup branch and remove the files from the working tree (`git rm --cached path` or `git rm path`).
2. Use `git filter-repo` or BFG to remove large files from history, e.g.:
   - `git filter-repo --path actions-runner-1772733156/externals/node24_alpine/bin/node --invert-paths`
3. Push the cleaned branch and open a PR; coordinate force-push to main if accepted.
4. Store the runner binaries in `artifacts/` (gitignored) or an external S3 or Release asset and add a small downloader script in `scripts/`.

Option C — Replace with download-on-demand
1. Remove the committed binaries and add a `scripts/fetch-runner-binaries.sh` that downloads appropriate runner builds from releases or S3.
2. Update CI to call the script during setup.

Notes & Warnings
- Rewriting history requires coordination (force-push) and will disrupt forks/PRs. Only proceed after team agreement.
- Using Git LFS requires enabling LFS for the repository and possibly increasing storage billing for LFS usage.
- I can prepare a PR that implements Option C (remove files from HEAD and add a fetch script + docs), or implement Option A by adding `.gitattributes` and performing the `git lfs migrate` steps if you approve.

Suggested next action: review and confirm preferred remediation option. If you want, I will prepare a PR implementing Option C to avoid immediate history rewriting and large-file migration.