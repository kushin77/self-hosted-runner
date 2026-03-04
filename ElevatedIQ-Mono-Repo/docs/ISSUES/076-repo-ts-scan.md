Title: Repo-wide TypeScript usage scan and per-package triage (Issue #76)

Description:
- Run a repository-wide scan to identify TypeScript usage, packages with `tsconfig.json`, and packages lacking type checks in CI.
- Produce triage issues for packages that need type enforcement, along with a recommended priority list.

Acceptance Criteria:
- A report (markdown) listing all packages, their type-check status, and recommended remediation steps.
- Created issues for top-priority packages (e.g., `apps/portal`, `services/*`) with suggested action items.

Suggested Plan:
1. Run a script that finds `tsconfig.json` files and runs `tsc --noEmit` for each package.
2. Collect failures and categorize by severity and estimated effort.
3. Create per-package issues (or a single aggregated report) and attach to the backlog.

Notes:
- Consider automating this using a CI job (`.github/workflows/ts-check.yml`) to enforce progress.
