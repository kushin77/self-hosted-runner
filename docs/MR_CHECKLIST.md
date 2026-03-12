# Migration MR Checklist

Use this checklist when reviewing the `automation/gitlab-migration` MR.

- [ ] Confirm `.gitlab-ci.yml` matches org runner policies and executor choices.
- [ ] Verify `scripts/gitlab-automation/README.md` and `docs/GITLAB_CI_SETUP.md` cover required CI variables.
- [ ] Ensure `GITLAB_TOKEN` is set as a masked CI variable with `api` scope before enabling live tests.
- [ ] Run `SKIP_ISSUE_TEST=true` validation pipeline on MR and confirm no errors.
- [ ] Review `create-required-labels-gitlab.sh` payloads for label naming and colors.
- [ ] Confirm `triage-issues-gitlab.sh` and `sla-monitor-gitlab.sh` behavior and assignee mapping.
- [ ] Verify helper scripts `create-ci-variables-gitlab.sh` and `create-schedule-gitlab.sh` are acceptable for ops usage.
- [ ] Plan runner host migration steps from `docs/GITLAB_RUNNER_MIGRATION.md` and schedule downtime if needed.

Optional post-merge steps:
- Add pipeline schedules via `create-schedule-gitlab.sh` or CI UI.
- Run `create-required-labels-gitlab.sh` with a service token to ensure labels exist.
- Enable `sla` schedule and monitor first report.
