Title: EPIC-2 failover blocked — missing GCE backend-service; Cloud Run present

Summary:
During EPIC-2 live failover (traffic shift stage 1: 10%), the orchestration failed because the script attempted to update a GCE backend-service named `nexus-shield-backend` which does not exist in the project. The project is using Cloud Run services (`nexus-shield-portal-backend` / `nexus-shield-portal-frontend`).

Findings:
- GCP project: nexusshield-prod
- Compute API: enabled
- No global backend-services or URL maps found.
- Cloud Run services present: `nexus-shield-portal-backend`, `nexus-shield-portal-frontend`, `nexusshield-portal-backend-production` (detected)
- Audit log: `logs/epic-2-migration/gcp-migration-20260311T030851Z.jsonl` shows: "Traffic shift to 10% failed"

Impact:
- Live failover aborted at stage 1 (10%) due to missing backend-service.
- Safe remediation required before further automated staged traffic shifts.

Remediation options (recommended order):
1) Use Cloud Run traffic-splitting APIs to perform staged traffic shifts (preferred).
   - Implement staged percentages by updating Cloud Run service traffic between revisions or tagged revisions.
   - Script already updated to support Cloud Run path; to auto-run, set `AUTO_APPROVE_CLOUDRUN=true` in the environment for the orchestration.
2) Alternatively, provision a GCE backend-service + serverless NEG and URL map to integrate Cloud Run with a global load balancer, then the existing GCE-based flow can be used (more complex).
3) If operator approval is required, leave as-is and document steps in this issue for manual intervention.

Next steps taken by automation:
- Updated `scripts/epic-2-gcp-migration.sh` to detect Cloud Run services and provide an opt-in Cloud Run traffic-update flow (requires `AUTO_APPROVE_CLOUDRUN=true`).
- Created this issue file with findings and recommended remediation.

Suggested immediate action:
- If you want the automation to proceed now, set `AUTO_APPROVE_CLOUDRUN=true` and re-run `PHASE=failover DRY_RUN=false /home/akushnir/self-hosted-runner/scripts/epic-2-gcp-migration.sh`.
- If you prefer a safer manual approach, review the issue and approve via GitHub when ready.
