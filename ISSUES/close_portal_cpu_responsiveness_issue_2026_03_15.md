# Close: Portal CPU Spike and Non-Responsive UI

Status: Closed
Date: 2026-03-15
Scope: frontend/dashboard (feature-rich dashboard implementation)

Issue summary:
- Browser UI became non-responsive and client CPU spiked during dashboard usage.
- Root causes were overlapping polling loops, non-cancelable requests, and expensive repeated raw JSON rendering.

Action taken:
- Replaced fixed setInterval polling with self-scheduling, non-overlapping polling loops.
- Added request cancellation and deterministic timeout handling via AbortController.
- Removed unsupported fetch timeout usage and implemented explicit timeout cancellation.
- Added throttled API error logging to prevent console log storms under failure conditions.
- Bounded raw metrics JSON rendering and made it user-toggleable to reduce main-thread work.
- Installed and pinned missing build dependency (terser) required by current Vite config.
- Added timeout/cancellation support in TypeScript API client for portal frontend service calls.
- Added non-overlapping in-flight guards to TypeScript dashboard refresh loops.
- Added frontend entrypoint async loading (`React.lazy` + `Suspense`) to reduce initial main-thread pressure.
- Added deterministic Vite chunk splitting with dedicated `recharts` vendor chunk for lower parse/compile overhead at startup.

Files updated:
- frontend/dashboard/src/api.js
- frontend/dashboard/src/pages/Dashboard.jsx
- frontend/dashboard/src/pages/Metrics.jsx
- frontend/dashboard/package.json
- frontend/dashboard/package-lock.json
- frontend/src/services/api.ts
- frontend/src/components/Dashboard_v2.tsx
- frontend/src/components/SecretsManagementDashboard.tsx
- frontend/src/main.tsx
- frontend/vite.config.ts

Validation:
- Static diagnostics: no editor errors in modified source files.
- Production build: successful via npm run build in frontend/dashboard.
- Production build: successful via npm run build in frontend.
- Live smoke probe: `http://192.168.168.42:3919` returned 200 with single JS asset size ~750195 bytes before optimization update.
- Post-optimization local build output: entry bootstrap ~2.20 kB, dashboard chunk ~13.87 kB, shared vendor ~141.91 kB, recharts vendor ~383.32 kB.

Operational policy alignment:
- Immutable: issue closure and remediation are append-only in repository history.
- Ephemeral: all request auth headers are runtime-injected; no new secret persistence paths added.
- Idempotent: polling loop design prevents request fan-out and safely re-runs on schedule.
- No-ops / Hands-off: fully automated periodic refresh with bounded resource usage and cleanup on unmount.
- Credential architecture: no changes were made to GSM/Vault/KMS secret authority boundaries.
- Direct development + direct deployment: changes are ready for direct deploy workflow.
- No GitHub Actions + no PR release flow: no workflow or PR-release mechanisms were introduced.
