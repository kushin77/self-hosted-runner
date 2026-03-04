## Runner Cleanup & Remediation Runbook

Purpose
-------
This runbook describes the steps to remediate self-hosted GitHub Actions runner workspace permission issues that cause `EACCES` errors when workflows attempt to clean or remove persisted directories such as `apps/portal/node_modules` and `.backups`.

Files
-----
- `scripts/pmo/runner_cleanup.sh` — executable script that performs audited cleanup and permission normalization. Intended to be executed on the runner host as root (or with sudo).

Quick remediation (recommended)
------------------------------
1. SSH to each runner host as an operator with sudo privileges.
2. Review the `scripts/pmo/runner_cleanup.sh` script and run a dry-run first:

```bash
sudo bash scripts/pmo/runner_cleanup.sh --dry-run
```

3. If output looks correct, run the script for real:

```bash
sudo bash scripts/pmo/runner_cleanup.sh
```

4. After remediation, re-run the Phase 3 validation workflows (CI) and confirm acceptance criteria: two consecutive successful runs per affected workflow.

Notes & Safety
--------------
- The script will attempt to stop/start runner services and remove `node_modules` and `.backups` directories under the runner `_work` tree. Run only during maintenance windows.
- Prefer to run on a non-production runner first to validate behavior.

Acceptance criteria
-------------------
- Two consecutive successful workflow runs for each affected workflow after remediation.
- No EACCES errors in the checkout/cleanup phases on subsequent runs.

Contacts
--------
- Primary operator: `akushnir`
