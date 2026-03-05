Title: Implement CI/CD 4-layer foundation

Description:
- Add the 4-layer CI/CD documentation and example Tekton pipeline under `.ci/`.
- Wire up GitOps repos and create skeleton manifests for platform components (ArgoCD, Tekton, OPA, Observability).

## Status

Completed: 2026-03-05

Resolution: Design and documentation for the 4-layer CI/CD architecture were completed, reviewed, and implemented. See DELIVERY_COMPLETION_REPORT.md and FINAL_DELIVERY_SUMMARY.md for details.

Acceptance Criteria:
- Documentation added in `docs/*` and `diagrams/*`.
- Example Tekton pipeline present at `.ci/tekton-pipeline.yaml`.
- Create follow-up issues for platform installation and GitOps repo bootstrapping.

Assignees: devops-platform
Labels: proposal, epic
