# Deploy Ollama-enabled runner AMI and validate in staging

## Goal
Build and deploy the updated runner AMI (includes Ollama) and validate agentic workflows in staging.

## Acceptance Criteria
- New AMI built via Packer with Ollama service installed and enabled
- Staging runners launched from new AMI and registered with GitHub
- Integration test suite (`tests/integration-agentic-workflows.sh`) runs and passes on staging runners
- Create and merge a test PR to validate `auto-fix` workflow runs end-to-end
- Any issues found are documented and triaged

## Tasks
- [ ] Run: `cd packer && packer build -var="build_id=$(date +%s)" runner-image.pkr.hcl`
- [ ] Launch staging instances from the AMI
- [ ] Ensure `ollama` systemd service is `active` on each runner
- [ ] Run integration tests on staging runners
- [ ] Open test PR `test/auto-fix-demo` and verify workflow execution
- [ ] Close this tracking file or mark done when staging validation is successful

## Notes
- Branch: `feature/ci-portal-staging-e2e` contains the implementation and compiled workflows
- Tests: `tests/integration-agentic-workflows.sh` already passes locally (38/38)

Created-by: GitHub Copilot
Date: 2026-03-04
