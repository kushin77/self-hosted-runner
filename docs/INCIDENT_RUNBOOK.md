# Incident Runbook — Governance Enforcement

Owner: Platform Security / Automation Team

1. Symptoms
- Cloud Run `prevent-releases` high error rate or crashes
- Cloud Scheduler job failing or disabled
- GitHub API 401/403 errors when enforcement runs
- Secrets access denied in Cloud Run logs

2. Immediate actions
- Check Cloud Run logs: `gcloud logs read "resource.type=cloud_run_revision resource.labels.service_name=prevent-releases" --project=nexusshield-prod --limit=100`
- Check Scheduler job: `gcloud scheduler jobs describe prevent-releases-poll --project=nexusshield-prod --location=us-central1`
- Check secret access policy: `gcloud secrets get-iam-policy github-token --project=nexusshield-prod`

3. Rollback / Emergency stop
- Disable Cloud Scheduler job:
  `gcloud scheduler jobs pause rotate-github-token-reminder --project=nexusshield-prod --location=us-central1`
  `gcloud scheduler jobs pause prevent-releases-poll --project=nexusshield-prod --location=us-central1`
- Restrict Cloud Run invoker temporarily to owner: `gcloud run services remove-iam-policy-binding prevent-releases --member=serviceAccount:nxs-scheduler-sa@nexusshield-prod.iam.gserviceaccount.com --role=roles/run.invoker`
 - If webhook abuse is suspected, remove unauthenticated invocation immediately:
   `gcloud run services remove-iam-policy-binding prevent-releases --member=allUsers --role=roles/run.invoker --project=nexusshield-prod --region=us-central1` 
   Then re-add only the scheduler SA when safe.

4. Token compromise remediation
- Immediately rotate `github-token` following `docs/ROTATE_GITHUB_TOKEN.md` and use `scripts/secrets/rotate-github-token.sh` to add a new secret version.
- Revoke old tokens in GitHub (manually via UI or GitHub admin APIs).
- Redeploy `prevent-releases` if it requires env var refresh.

5. Post-incident
- Create a post-mortem issue in the repo with timeline and remediation steps.
- Update `docs/ALERTING_AND_MONITORING.md` with any new alerts implemented.
