Title: Optional near-instant GitHub mirror via CI push job

Goal: Provide an optional CI job that runs on successful merge to `main` to `git push --mirror` to the private GitHub backup (near-instant). Document security tradeoffs.

Checklist:
- [ ] Create a protected job in `.gitlab-ci.yml` that runs only on `main` merges and has `only: [protected]` and required approvers.
- [ ] Configure a deploy SSH key stored as a protected CI/CD variable or secret file; document key rotation.
- [ ] Add safety checks: prevent pushing protected branches to GitHub if GitHub protects them differently.
- [ ] Add tests to ensure the job runs and verifies mirror updated within the pipeline.
- [x] Template added: `ci_templates/mirror-to-github.yml` (needs wiring into `config/cicd/.gitlab-ci.yml` and protection settings).

Security tradeoffs:
- Runner will hold an SSH key capable of writing to GitHub — protect and rotate frequently. This bypasses GitLab-side mirror rate/queue.
