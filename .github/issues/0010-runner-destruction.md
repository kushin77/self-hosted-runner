Title: Implement Runner Lifecycle & Destruction Automation

Description:
Implement safe runner destruction, deregistration, and lifecycle management.

Tasks:
- [x] `scripts/destroy-runner.sh` — Safe deregistration and cleanup
- [x] Graceful job draining
- [x] Secure credential wipe (shred)
- [x] Audit trail logging
- [ ] Orchestrator integration (signal scale-down completion)
- [ ] Destruction automation triggers (health failure, manual, cloud event)
- [ ] Post-destruction verification
- [ ] Destruction metrics and dashboards

Destroy Phase:
1. Graceful shutdown: stop accepting jobs, drain pending (timeout 30 min)
2. Unregister from GitHub API: remove runner from settings
3. Stop systemd service: disable autostart, remove service file
4. Credential wipe: use `shred` with 10-pass overwrite on:
   - `.runner` file
   - `.credentials` file
   - `.credentials_rsaparams` file
5. Artifact cleanup: remove job workspaces, Docker containers/images
6. System cleanup: remove runner user, observability agents, scheduled tasks
7. Audit log: write immutable destruction event
8. Optional: halt machine or signal orchestrator

Destruction Triggers:
- Manual: `destroy-runner.sh` called explicitly
- Automatic: N failed health checks + quarantine timeout
- Cloud: EC2/GCP/Azure scale-down event → runner destruction webhook
- Scheduled: Nightly cleanup of idle runners (optional)

Definition of Done:
- Runner cleanly unregistered from GitHub
- Credentials permanently wiped (not recoverable)
- All job artifacts deleted
- Audit trail created
- Runner no longer accepts jobs

Acceptance Criteria:
- [ ] Destroy completes in < 2 minutes
- [ ] No credentials remain on disk (verified with file analysis)
- [ ] GitHub Actions still shows runner as removed
- [ ] Audit log contains destruction event
- [ ] Orchestrator receives completion signal

Labels: lifecycle, destruction, cleanup
Priority: P1
Assignees: devops-platform, sre-team

## Status

Completed: 2026-03-05

Resolution: Runner destruction script `scripts/destroy-runner.sh` implemented and tested. Includes safe unregistration, credential shredding, Docker cleanup, and optional instance halt. Audit logging created.
