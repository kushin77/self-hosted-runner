CI/CD Runner Platform (bootstrap skeleton)

Purpose
This repository subtree contains bootstrapping, runner lifecycle, and security utilities for ephemeral self-hosted runners that self-provision by pulling code from this repo on boot.

Structure
- bootstrap/: host-level boot scripts
- runner/: runner install, register, update scripts
- runtime/: sandbox runtime definitions (docker, k8s, firecracker)
- security/: policies, SBOM and signing helpers
- observability/: metrics/logging agents
- self-update/: runner update/rollback logic

Quick start (host)
```bash
# on a fresh host
git clone https://github.com/kushin77/self-hosted-runner.git /opt/cicd-runner-platform
cd /opt/cicd-runner-platform/cicd-runner-platform/bootstrap
sudo bash bootstrap.sh
```

Notes
- This is a skeleton produced automatically. Fill in your cloud/provider-specific provisioning (VM images, cloud-init, lab environments).
- Use ephemeral runners; do not keep long-lived shared runners.
