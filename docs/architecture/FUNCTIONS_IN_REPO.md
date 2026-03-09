The following functions were discovered by searching the repository for named
`function` declarations.  These represent logical units that could be
"represented in the portal" (e.g. via documentation pages or UI endpoints).

### Shell helper functions
- `record_result()` – tests/performance/run-performance-benchmarks.sh
- `run_test()` – tests/smoke/run-smoke-tests.sh
- `run_test_timeout()` – tests/smoke/run-smoke-tests.sh
- `assert_test()` – tests/vault-security/run-vault-security-tests.sh
- `skip_test()` – tests/vault-security/run-vault-security-tests.sh
- `assert_test()` – tests/integration/provisioner-integration-tests.sh

### Node.js service library functions
- `startMetricsServer(port = 9090, app = null)` – services/provisioner-worker/lib/metricsServer.js
- `stopMetricsServer()` – services/provisioner-worker/lib/metricsServer.js
- `getSummary()` – services/provisioner-worker/lib/metricsServer.js
- `writeLocal(event)` – services/provisioner-worker/lib/audit.cjs
- `log(event)` – services/provisioner-worker/lib/audit.cjs
- `formatMessage(level, msg, meta)` – services/provisioner-worker/lib/logger.js
- `log(level, msg, meta = {})` – services/provisioner-worker/lib/logger.js
- `error(msg, meta = {})`,`warn(...), info(...), debug(...)` – convenience wrappers in logger.js
- `child(fixedMeta = {})` – create child logger
- `genCorrelationId()` – helper to generate IDs in logger.js
- `runCommand(cmd, args, opts = {})` – services/provisioner-worker/lib/terraform_runner_cli.js

---

> 💡 **Next step**: decide how these functions should appear in the portal (e.g. as
> documentation cards, an API reference, or runtime controls).  For now this
> file records what exists in the repo.  You can link to it from the React
> portal if desired.