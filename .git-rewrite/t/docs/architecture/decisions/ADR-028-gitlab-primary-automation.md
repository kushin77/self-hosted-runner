# ADR-028: GitLab Primary Mono-Repo Automation

## Status
Approved (Solo Execution Mode)

## Context
The ElevatedIQ Mono-Repo requires a unified, high-velocity automation engine to handle CI/CD, PMO enforcement, and NIST 800-53 compliance auditing. As a top 0.01% FAANG-level project, we require zero-trust pipelines and extreme velocity.

## Decision
GitLab CI is designated as the primary orchestration engine for all repository-level automation, including:
1.  **NIST 800-53 Compliance**: Automated auditing of CM-3 and PM-5 controls.
2.  **PMO Enforcement**: Real-time status tracking, dashboard generation, and assignee enforcement.
3.  **Security Gates**: Snyk testing and secret scanning on every commit.
4.  **Quality Assurance**: Unified linting (Ruff, Shellcheck, TFLint) and testing (Pytest).

## Consequences
- The `.gitlab-ci.yml` becomes the central authority for repository hygiene.
- All code changes must satisfy the "Governance" stage before being considered for production.
- GitHub actions may still be used for GitHub-specific tasks, but GitLab remains the primary worker.
- Architecture decisions and PMO metrics will be automatically updated by the pipeline.

## NIST Control Mapping
- **CM-3**: Configuration Change Control - implemented via GitLab MR gates and automated audits.
- **PM-5**: Project Management Plan - implemented via PMO dashboard automation.
- **AU-2**: Audit Events - all CI/CD actions are logged in persistent GitLab logs.
