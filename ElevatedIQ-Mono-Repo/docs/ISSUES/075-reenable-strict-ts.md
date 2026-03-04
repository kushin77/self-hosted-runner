Title: Re-enable strict TypeScript flags in `apps/portal/tsconfig.json`

Description:
- The `apps/portal` package currently has relaxed TypeScript compiler options to reduce noise while migrating. We should re-enable stricter flags (noImplicitAny, strictNullChecks, noUnusedLocals/noUnusedParameters, etc.) incrementally and fix any errors that surface.

Acceptance Criteria:
- `cd apps/portal && npm run type-check` succeeds with the targeted stricter flags enabled.
- PR(s) created per rule or grouped logically to keep reviews small.

Suggested Plan:
1. Create a branch `chore/portal-strict-1` enabling a subset of strict flags (e.g., `noUnusedLocals`, `noUnusedParameters`).
2. Fix errors and run `npm run type-check` until green.
3. Enable next group of flags (`noImplicitAny`, `strictNullChecks`) on `chore/portal-strict-2` and fix remaining errors.
4. Repeat until full `strict: true` is enabled.

Notes:
- Keep changes localized to `apps/portal` unless cross-package types require broader fixes.
- Open PR(s) against `chore/portal-eslint-baseline` or `main` as appropriate.
