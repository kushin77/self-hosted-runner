# Portal UI Unresponsive  Investigation (2026-03-06)

**Summary**
- Browser shows "Page Unresponsive" loading RunnerCloud Portal at http://192.168.168.42/sc
- Server-side (Caddy + Portal) were healthy and responding; issue appears in client browser.

**What I ran**
- Collected host diagnostics (`docker ps`, `docker stats`, logs)
- Inspected `/tmp/eiq_diag_*` for logs and error grep

**Key findings**
- `eiq-portal` replies with 200/304; assets served, no server errors.
- `eiq-caddy` logs show earlier 502s to obsolete ports (fixed); current runtime normal.
- Portal container CPU usage near 0%; not a server resource problem.
- Grep of recent portal logs for error/warn/exception returned no hits.

**Likely root cause**
- Client-side renderer hang due to large or blocking JavaScript bundle.

**Immediate remediation (user)**
1. Open DevTools (Console & Network) to look for long-running scripts, pending XHRs, or errors.
2. Try Incognito or different browser to rule out cache/extensions.
3. Hard refresh/clear site data and retry.

**Further actions if browser confirms
**
- Rebuild frontend with smaller bundles or code splitting.
- Upload a HAR file or console logs for deeper investigation.

**Actions taken**
- Collected data; no backend anomaly. Documented findings in this file.

**Next steps**
- I can fetch main JS bundle from within portal container to measure size.
- Restart `eiq-portal` if blockage persists; watch logs.
- Create a PR or issue to track frontend performance if required.

**Diagnostic snapshot**
- `/tmp/eiq_diag_*` on host contains the full outputs.

Please attach DevTools output or HAR and indicate if you want the portal service restarted now.