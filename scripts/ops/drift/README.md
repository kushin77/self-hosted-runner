Drift detection helper

Run locally (requires docker):

```bash
# run from repo root
docker run --rm -v "$PWD":/workspace -w /workspace hashicorp/terraform:1.5.5 /bin/sh -c './scripts/ops/drift/run_drift.sh'
```
