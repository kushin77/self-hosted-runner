# Disable GitHub Actions workflows (Operational Directive)

Action taken: All active GitHub Actions workflows have been disabled and moved to `.github/workflows/.disabled/` per the operational directive to pause CI/CD and require direct-deploy to the approved worker node `192.168.168.42`.

Files moved/changed:

- `.github/workflows/auto-provision-fields.yml` -> `.github/workflows/.disabled/auto-provision-fields.yml` (disabled)
- Existing `.github/workflows/.disabled/` files preserved

Rationale:
- CI/CD is paused; all deployments and validation must be performed on the approved worker node.
- Disabling Actions prevents accidental runs and leaking of ephemeral credentials via GitHub Actions.

Next steps & verification:
- Confirm that no workflows are listed as active in `.github/workflows/` (should only contain .reregister markers).
- If any additional workflow files are added later, ensure maintainers move them to `.github/workflows/.disabled/` until Ops lifts the pause.

If you want, I can: create a GitHub Issue linking this change and request Ops review, or open a PR with the change (current branch already pushed).