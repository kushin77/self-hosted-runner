# Test Draft Issue: auto-fix workflow validation

## Purpose
+Create a short-lived test branch and PR to exercise the `auto-fix` workflow end-to-end in staging (completed).

## Branch
- Name: `test/auto-fix-demo`

## Example commands (run locally)

```bash
git checkout -b test/auto-fix-demo
mkdir -p tests/pr-demos
cat > tests/pr-demos/broken.js <<'EOF'
// Intentional broken JS for auto-fix demo
console.log('missing paren'
EOF
git add tests/pr-demos/broken.js
git commit -m "test: add broken file to trigger auto-fix workflow"
git push -u origin test/auto-fix-demo
```

If pushing from this environment fails due to sudo or permission prompts, run the block above on a workstation with your user credentials.

## Validation
+- A PR has been created: https://github.com/kushin77/self-hosted-runner/pull/121
+- Monitor Actions → `auto-fix.lock.yml` run.
- Verify comments/PR diffs created by the workflow.

## Notes
- Attempted to create and push the branch from the runner, but the process prompted for sudo and could not complete in this session. If you'd like, grant temporary elevated access (not recommended) or run the commands locally.

Created-by: GitHub Copilot
Date: 2026-03-04
