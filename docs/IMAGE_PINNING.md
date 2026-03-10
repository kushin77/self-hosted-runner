# Image Pin Automation

This documents the automated image-pin updater.

Usage:

1. Edit `ci/image_pin_mappings.json` with mappings of `old_image: new_image`.
2. Run the runner on the deployment host:

```bash
bash scripts/image-pin-runner.sh
```

This will update Terraform files under `terraform/` in-place and create a local git commit with the provided message. This repository follows direct-development and direct-deployment policies: no PRs and no GitHub Actions.
