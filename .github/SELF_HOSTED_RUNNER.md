Self-hosted runner guidelines
=================================

This repository's CI is expected to run on the organization's self-hosted runner infrastructure. The workflows reference the `self-hosted` label and `linux` label; ensure your runners match these labels.

Recommended runner labels and capabilities:
- `self-hosted` (required)
- `linux` (required)
- `docker` or `containerd` (required for workflows that run containers / kind)
- `kind` (optional) - if present, workflows can create `kind` clusters
- `helm` (optional) - or ensure Helm is installed on runner
- `terraform` (optional) - or ensure Terraform is available

Prerequisites for integration workflows:
- Docker engine installed and running on the runner host
- `kind` available in PATH
- `kubectl`, `helm`, and `terraform` available in PATH
- Sufficient CPU/memory to run a small cluster (recommend at least 4 vCPUs and 8GB RAM per concurrent integration job)

If your runners use different labels, update the workflow `runs-on` arrays accordingly.
