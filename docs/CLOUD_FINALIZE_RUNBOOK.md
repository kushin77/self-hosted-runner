Cloud Finalize Runbook
======================

Purpose
-------
This document shows the exact commands the cloud operator should run to perform the final cloud deployment step and provide an auditable log for Issue #2311.

Preconditions
-------------
- You have a GCP service-account JSON file with the required permissions.
- You have a checked-out copy of the repository and are at its root.

Steps (copy-paste)
------------------
1. Export credentials (example):

```bash
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
```

2. Run the safe wrapper (produces a timestamped log under /tmp and a .sha256 file):

```bash
bash scripts/go-live-kit/run-cloud-finalize-wrapper.sh
```

3. When complete, attach or paste the full contents of the generated `/tmp/go-live-finalize-*.log` to Issue #2311. Also include the SHA256 from `/tmp/go-live-finalize-*.log.sha256`.

Notes
-----
- The wrapper runs `scripts/go-live-kit/02-deploy-and-finalize.sh` and captures combined stdout/stderr. The auto-verifier will consume the pasted log and close Issue #2311 if heuristics pass.
- If you need to re-run, keep the log files for audit; each run produces a unique timestamped filename.
