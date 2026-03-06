# CI Migration Guide — Replace GitHub Actions with In-Repo Scripts

Objective
---------
Provide a repeatable migration path to remove reliance on external action marketplace components and run pipelines fully on self-hosted infrastructure.

Strategy
--------
1. For each `uses:` action in `.github/workflows`, either:
   - Replace with an equivalent in-repo script (see `ci/scripts/`), or
   - Vendor the action code into `ci/actions/` and run locally.
2. Ensure secrets are provided by Vault and injected as environment variables.
3. Update workflows to guard steps that require hosted actions with `if: runner.labels contains 'self-hosted'`.

Example replacement (setup-node):

Original:
```
- name: Use Node.js
  uses: actions/setup-node@v4
  with:
    node-version: '20'
```

Replacement (self-hosted runners):
```
- name: Install Node (self-hosted)
  if: contains(runner.labels, 'self-hosted')
  run: |
    ci/scripts/setup-node.sh
```

Migration checklist
-------------------
- [ ] Locate all `uses:` references (inventory done).
- [ ] Create in-repo script or vendor action for each usage.
- [ ] Update workflows with conditional steps.
- [ ] Test on staging self-hosted runners.
- [ ] Remove or archive external action usage once validated.

Notes
-----
Keep GitHub-hosted-compatible paths where you need public CI; prefer feature parity and avoid breaking existing PR signal until runners are fully validated.
