# GitHub Issues Tracker (local copy)

This file is a local tracker of GitHub issues for the `self-hosted-runner` repo.
If remote issue creation fails, maintainers can copy these entries to GitHub Issues.

---

## OPEN / TO CREATE (Phase 2 → Phase 3)

1. Feature: Deploy Mode Wizard - 3-Mode Setup Flow
   - Labels: feature, phase-p2, ui, high-priority
   - Body: Implement wizard for Managed/BYOC/On-Prem + CLI commands, validation, progress UI.
   - Assignees: @kushin77

2. Feature: API Integration Layer
   - Labels: feature, infrastructure, backend
   - Body: Add API client abstraction in portal, endpoints for runners, events, billing, cache, ai-oracle.
   - Assignees: backend-team
   - Status: PARTIALLY IMPLEMENTED — `AIOracle`, `Runners`, `Security`, `Billing`, `LiveMirrorCache` wired to `src/api` (local mock responses). Replace `api.useMock` to `false` when backend is ready.

3. Feature: Instant Deploy (zero-to-live <5m)
   - Labels: critical-path, feature, p2
   - Body: Implement instant deploy flow, bootstrap scripts, preflight checks, telemetry, rollback.
   - Assignees: release-owner

4. Feature: eBPF Event Stream WebSocket
   - Labels: feature, security, p2
   - Body: Replace simulated stream with WebSocket server for Falco/Tetragon events; scale testing.
   - Assignees: security-team

5. Feature: TCO Calculator Integration & Validation
   - Labels: feature, billing, p2
   - Body: Hook billing page to real metrics; add export and CI tests for cost calculations.
   - Assignees: finance-eng

6. Feature: Windows Runners - Beta Support
   - Labels: feature, windows, p3
   - Body: Add driver/patch guidance, sandboxing, GPU support verification, image building docs.
   - Assignees: platform-team

7. Bug: UI: Missing keyboard focus indicators on Settings inputs
   - Labels: bug, accessibility
   - Body: Ensure keyboard focus visible on all interactive controls and inputs in `Settings.tsx`.
   - Assignees: frontend-team

8. Chore: Add CI job to run portal TypeScript compile checks
   - Labels: chore, ci
   - Body: Add GitHub Actions job for `pnpm build` / `tsc --noEmit` on PRs
   - Assignees: ci-team

9. Docs: Release notes and Phase 2 executive summary
   - Labels: docs
   - Body: Publish `PHASE_2_EXECUTION_SUMMARY.md` to repo root and tag release candidate.
   - Assignees: docs-owner

---

## CLOSED / DONE

- feat: complete Phase 2 UI implementations - Security, Billing, App integration (committed)
- feat: add Deploy Mode Wizard (local implementation added)

---

## How to create these issues remotely

If you have `gh` installed and authenticated, run:

```bash
gh issue create --title "Feature: Deploy Mode Wizard - 3-Mode Setup Flow" --body "<body>" --label feature,phase-p2,ui --assignee kushin77
```

Or copy entries above into the GitHub Issues UI for the repo `kushin77/self-hosted-runner`.
