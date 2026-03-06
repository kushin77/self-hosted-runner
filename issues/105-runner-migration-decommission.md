#105 — Runner Migration & Legacy Runner Decommissioning

Status: Open
Owner: @kushin77, Platform team

Purpose
-------
After the new Kubernetes-based GitLab Runner passes validation (issue #104), this issue coordinates the migration of CI workloads to the new runner and safe decommissioning of legacy runners with a rollback window.

Prerequisites
--------------
- Issue #104 completed: validation passed, runner is Online
- `YAMLtest-sovereign-runner` job passed
- Test pipelines run successfully on the new runner
- Rollback plan in place (legacy runners remain enabled during rollback window)

Migration Strategy (Zero-Downtime)
---------------------------------
1. **Enable new runner in group/project** (already done via registration)
2. **Run critical test pipelines** on new runner to verify behavior
3. **Monitor for 24-48 hours** while both runners accept jobs
4. **Verify no regressions** in job logs, timings, or outputs
5. **Disable legacy runners** once confidence is high
6. **Keep disabled runners for 7 days** in case of rollback

Steps
-----

### Phase 1: Dual-Runner Period (24-48 hours)
- [ ] Both old and new runners are Online in GitLab
- [ ] Update `.gitlab-ci.yml` to test job distribution:
  - Option A: Use runner tag `k8s-runner` for new jobs
  - Option B: Use explicit runner ID for controlled rollout
- [ ] Trigger at least 3 full pipelines on main and feature branches
- [ ] Monitor logs and metrics:
  ```bash
  kubectl -n gitlab-runner logs -l app=gitlab-runner --tail=500 | grep -E "Received job|Finished job|ERROR"
  ```
- [ ] Record observations: job duration, error rates, image pulls

### Phase 2: Legacy Runner Disable (if Phase 1 passes)
After successful dual-runner validation:
- [ ] In GitLab UI (Admin → Runners), disable legacy runner(s)
- [ ] Monitor job queue: new jobs should land on k8s-runner only
- [ ] Continue monitoring for 24 hours

### Phase 3: Rollback Window (7 days)
- [ ] Keep disabled legacy runners available
- [ ] If critical issue arises: re-enable legacy runner, disable k8s-runner, investigate
- [ ] After 7 days with no issues: delete legacy runner registration

### Phase 4: Cleanup & Documentation
- [ ] Remove old runner configuration from repository docs
- [ ] Update `.gitlab-ci.yml` to document exclusive use of k8s-runner
- [ ] Archive legacy runner logs/metrics
- [ ] Update RUNBOOK for future operators

Success Criteria
----------------
- All critical pipelines pass on k8s-runner
- No observable regressions in job execution
- Job queue processes normally (no stalls)
- Log analysis shows clean registration and job lifecycle
- Legacy runner can be disabled without affecting in-flight jobs

Metrics to Track
----------------
1. **Job success rate**: % of passed jobs (target: >99%)
2. **Job duration**: compare with legacy runner baseline (acceptable variance: ±10%)
3. **Pod lifecycle**: time to ready, time to cleanup
4. **Image pull times**: are pulls cached or fresh each time?
5. **Error patterns**: any repeated failure modes

Rollback Procedure
------------------
If a critical issue is detected during Phase 2 or 3:
1. Re-enable legacy runner in GitLab UI
2. Disable new k8s-runner
3. Immediately re-run failing job on legacy runner
4. Gather diagnostic logs from both runners
5. Investigate root cause before re-enabling k8s-runner
6. Once resolved, repeat Phase 1 validation

Post-Migration Cleanup
---------------------
After 7-day rollback window with no issues:
1. Delete legacy runner from GitLab (remove registration)
2. Clean up any old SSH runner keys/certs
3. Archive metrics and logs
4. Document lessons learned in team wiki/runbook

Timeline
--------
- Phase 1 (dual-runner): Day 1-2
- Phase 2 (disable legacy): Day 3
- Phase 3 (rollback window): Day 3-10
- Phase 4 (cleanup): Day 10+

Notes
-----
- This is a cautious, zero-downtime migration strategy
- Ephemeral pods mean no persistent state carry-over; each job is isolated
- If k8s-runner becomes primary without issue, this can serve as pattern for future migrations
- Document any deviations from this plan for future reference
