## Owner unblock instructions — prevent-releases automated deploy

Status: AUTOMATION BLOCKED (no deployer SA key found on runner)

What happened
- The automated deploy orchestrator attempted to run but found no deployer service-account key on the runner and could not complete the final Cloud Run deployment due to IAM restrictions.

Immediate owner actions (choose one)
1) Run the bootstrap (recommended, idempotent)

   - As a Project Owner or IAM Admin, from the repository root run:

     ```bash
     PROJECT=nexusshield-prod bash infra/bootstrap-deployer-run.sh
     ```

   - This creates the `deployer-run` service account, grants the minimal roles the orchestrator needs, generates a JSON key temporarily, and stores the key in Google Secret Manager as `deployer-sa-key`.

2) Or create and upload a deployer key manually

   - Create the deployer SA and a JSON key in the project, then either:
     - Upload the key to this runner at `/tmp/deployer-sa-key.json`, or
     - Create a Secret Manager secret `deployer-sa-key` containing the JSON key.

Why this is needed
- The automation is intentionally designed to run fully automated and idempotent, but initial SA/key creation requires Owner-level permission. After bootstrap (or key upload), the orchestrator will continue and complete deployment without further manual steps.

After you complete one of the above
- Notify the automation by replying on the IAM issue or by uploading the key; the orchestration script will detect the key/secret and proceed immediately.

Related artifacts
- PR: #2618 — allow unauthenticated Cloud Run + secret injection
- PR: #2625 — deployer-role / instructions
- Diagnostics: `DEPLOYMENT_ERROR_DIAGNOSTICS.md`
- Bootstrap script: `infra/bootstrap-deployer-run.sh`

Contact
- If you want me to attempt a best-effort bootstrap run, provide the owner key on the runner (temporary), or confirm you will run the bootstrap and I will continue automatically.
