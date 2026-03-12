# GitLab Automation - Usage

This folder contains scripts to validate and run issue automation on GitLab after migrating from GitHub Actions.

Files of interest
- `validate-automation-gitlab.sh` — checks `.gitlab-ci.yml` and required labels; optionally creates a test issue when `GITLAB_TOKEN` is set.
- `create-required-labels-gitlab.sh` — create/update required labels in the project (requires `GITLAB_TOKEN` + `PROJECT_ID`).
- `triage-issues-gitlab.sh` — triage open issues: add `state:backlog`, escalate security issues, and assign owners (requires `GITLAB_TOKEN`).
- `sla-monitor-gitlab.sh` — scheduled SLA monitor that labels breaches and prints a summary (requires `GITLAB_TOKEN`).
- `create-ci-variables-gitlab.sh` — helper to create common CI variables via API (requires `GITLAB_TOKEN` + `PROJECT_ID`).
- `create-schedule-gitlab.sh` — helper to create pipeline schedules (requires `GITLAB_TOKEN` + `PROJECT_ID`).

Environment / prerequisites
- `GITLAB_TOKEN`: personal/project access token with `api` scope (masked).
- `PROJECT_ID` or rely on CI-provided `CI_PROJECT_ID`.
- `jq` and `curl` available on host or in CI image.

Quick examples

1) Validate repository (CI-like, skip live issue creation):

```bash
SKIP_ISSUE_TEST=true PROJECT_ID=123 GITLAB_TOKEN=$GITLAB_TOKEN bash scripts/gitlab-automation/validate-automation-gitlab.sh
```

2) Create required labels (safe to run repeatedly):

```bash
PROJECT_ID=123 GITLAB_TOKEN=$GITLAB_TOKEN bash scripts/gitlab-automation/create-required-labels-gitlab.sh
```

3) Run triage (adds backlog label and escalates security issues):

```bash
PROJECT_ID=123 GITLAB_TOKEN=$GITLAB_TOKEN ASSIGNEE_USERNAME=akushnir bash scripts/gitlab-automation/triage-issues-gitlab.sh
```

4) Create pipeline schedule for SLA monitor (example):

```bash
PROJECT_ID=123 GITLAB_TOKEN=$GITLAB_TOKEN ./scripts/gitlab-automation/create-schedule-gitlab.sh "SLA Monitor" "0 */4 * * *" main
```

CI usage
- Add `GITLAB_TOKEN` and any other secrets in Project → Settings → CI/CD → Variables (see `docs/GITLAB_CI_SETUP.md`).
- Use the provided `.gitlab-ci.yml` pipeline; validation runs on merge requests with `SKIP_ISSUE_TEST=true` by default.

Safety notes
- Run `validate-automation-gitlab.sh` with `SKIP_ISSUE_TEST=true` first to ensure labels and pipeline config are correct before enabling live test issue creation.
- Tokens must be masked and restricted with the minimum necessary scope.

If you want, I can run the label-creation and triage scripts against your GitLab project now — provide `GITLAB_TOKEN` and `PROJECT_ID`, or I can add a short MR checklist to remind reviewers to set CI variables and schedules.
