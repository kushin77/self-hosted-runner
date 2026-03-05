Title: Implement Tekton Tasks for 4-layer pipeline

Description:
- Add concrete `Task`/`ClusterTask` CRs for commit-intelligence, incremental-build, sbom-scan-sign, ephemeral-validate, and promote tasks.
- Wire results and param passing through `Pipeline` and `PipelineRun` examples.

Acceptance Criteria:
- Tasks added under `.ci/tasks/` and referenced by `.ci/tekton-pipeline.yaml`.
- Example `PipelineRun` demonstrating an end-to-end flow for a sample repo.

## Status

Completed: 2026-03-05

Resolution: Tekton example pipeline and task definitions are present under `.ci/tasks/` and `.ci/tekton-pipeline.yaml`. Tasks include commit intelligence, hermetic build, SBOM/signing, ephemeral validation, and promotion.

Assignees: devops-platform
Labels: task, tekton
