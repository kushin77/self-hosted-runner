# Issue 259 — Deploy guidance: enforce worker node targets

Action: per ops mandate, updated repository instructions and UI defaults to target the approved worker node `192.168.168.42`.

Files changed:

- `src/api/socket.ts` — socket default URL changed to `http://192.168.168.42:9090`
- `apps/portal/web/index.html` — demo API constant changed to `http://192.168.168.42:4000/api`
- `Makefile` — user-facing `http://localhost:...` examples updated to `http://192.168.168.42:...`

Rationale:
- Centralized deployments must use the approved worker node for all operational testing and validation while CI/CD is paused.
- These changes update developer-facing defaults and documentation so operators are directed to the canonical environment.

Notes & next steps:
- Many tests and local-only scripts still use `localhost` intentionally for local development. If you require a global replace of `localhost` in tests and harnesses, approve that separately; it will require wider test validation.
- I will now commit these changes on a feature branch and open a PR. Please advise if you want additional files (Makefile smoke-test commands, docker-compose healthchecks, or test harness defaults) updated to 192.168.168.42 as well.

Status: actioned and ready for review.
