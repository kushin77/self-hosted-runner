# Portal UI Unresponsive — Investigation Log

**Issue**: #370  
**Date**: 2026-03-06  
**Reporter**: ops-oncall  
**Status**: Root cause identified; targeted fix applied

---

## 1. Symptom Description

The portal dashboard (`portal.elevatediq.ai`) became unresponsive (frozen UI, no data updates) after the `eiq-api` service (managed-auth on port 9090) restarted or after a brief network interruption.  
Affected browsers: Chrome 122, Firefox 123 (cross-browser, ruling out browser-specific bugs).  
Reproduction: restart `eiq-api.service` on the worker node → portal freezes within 30 seconds.

---

## 2. Server Logs

Collected from the worker node (`192.168.168.42`) on 2026-03-05.

### 2a. eiq-api systemd journal (port 9090)

```
Mar 05 14:22:01 worker systemd[1]: eiq-api.service: Main process exited, code=exited, status=1/FAILURE
Mar 05 14:22:02 worker systemd[1]: eiq-api.service: Failed with result 'exit-code'.
Mar 05 14:22:08 worker systemd[1]: eiq-api.service: Scheduled restart job, restart counter is at 1.
Mar 05 14:22:08 worker systemd[1]: Started eiq-api.service.
Mar 05 14:22:09 worker node[14821]: Listening on port 9090
Mar 05 14:22:09 worker node[14821]: [socket.io] connection from ::1 (transport: polling)
Mar 05 14:22:09 worker node[14821]: [socket.io] connection from ::1 (transport: polling)
Mar 05 14:22:09 worker node[14821]: [socket.io] connection from ::1 (transport: polling)
Mar 05 14:22:09 worker node[14821]: [socket.io] connection from ::1 (transport: polling)
Mar 05 14:22:10 worker node[14821]: [socket.io] connection from ::1 (transport: polling)
Mar 05 14:22:10 worker node[14821]: [socket.io] connection from ::1 (transport: polling)
Mar 05 14:22:10 worker node[14821]: [socket.io] connection from ::1 (transport: polling)
Mar 05 14:22:10 worker node[14821]: [socket.io] connection from ::ffff:127.0.0.1 (transport: polling)
...  (58 additional connection events in the same second)
Mar 05 14:22:11 worker node[14821]: WARN: request queue length 128, latency degraded
```

> **Observation**: the server is flooded with socket.io connection attempts from the portal client immediately upon restart — a classic "reconnect storm" from a client configured with `reconnectionAttempts: Infinity`.

### 2b. Browser console (captured via DevTools)

```
[portal-socket] connect_error Error: xhr poll error
[portal-socket] connect_error Error: xhr poll error
[portal-socket] connect_error Error: xhr poll error
... (repeating every ~1 000 ms, no backoff visible)
```

### 2c. Network waterfall (DevTools — Network tab)

- `/socket.io/?EIO=4&transport=polling` requests queue up: 60+ pending requests
- `/metrics/summary` fetches accumulate behind the socket.io polling backlog
- Main thread blocked: `Long Task` of 1.4 s detected in Performance trace

---

## 3. Root Cause Analysis

| # | Location | Finding |
|---|----------|---------|
| 1 | `src/api/socket.ts` | `reconnectionAttempts: Infinity` — socket retries forever, generating a request storm on server restart |
| 2 | `src/api/client.ts` | `useMetrics` sets a 5 s polling interval **without** guarding against concurrent in-flight fetches; if a fetch takes > 5 s (during server overload), multiple fetches pile up |
| 3 | `src/App.tsx` | `useTick(2500)` triggers a re-render of the full component tree every 2.5 s, compounding the main-thread load during the storm window |

---

## 4. Fix Applied

**File**: `ElevatedIQ-Mono-Repo/apps/portal/src/api/socket.ts`

Changed `reconnectionAttempts` from `Infinity` to `10`.  After 10 failed attempts the socket stops retrying, preventing the storm. The `reconnect_failed` event is now emitted and surfaced to the Zustand store so the UI can display a "Connection lost — reload to reconnect" banner instead of silently freezing.

See diff in this PR.

---

## 5. Next Steps

### Immediate (Ops)

1. Verify `eiq-api.service` health after any restart:
   ```bash
   ssh akushnir@192.168.168.42 'sudo systemctl status eiq-api.service && curl -fsS http://localhost:9090/health'
   ```
2. Check for socket.io handshake flood in the journal:
   ```bash
   ssh akushnir@192.168.168.42 'sudo journalctl -u eiq-api.service -n 100 --no-pager | grep "socket.io"'
   ```

### Short-term (Frontend — tracked in #370)

3. Wrap `<Dashboard>` (and other data-heavy pages) in a React `ErrorBoundary` so a single component crash does not freeze the full portal.
4. Add an `AbortController` in `useMetrics` to cancel the in-flight fetch when a new tick fires, eliminating fetch pile-up.
5. Throttle `useTick` to 5 000 ms (matching the metrics interval) to halve the re-render frequency.

### Medium-term (Observability)

6. Add a Prometheus alert rule:
   ```yaml
   - alert: SocketIOHandshakeStorm
     expr: rate(socketio_connect_total[1m]) > 20
     for: 1m
     labels:
       severity: warning
     annotations:
       summary: "socket.io handshake rate spike on eiq-api"
   ```
7. Integrate a `/socket.io/metrics` endpoint in `eiq-api` and scrape it with the existing Prometheus setup.

---

## 6. Related Files

| File | Role |
|------|------|
| `ElevatedIQ-Mono-Repo/apps/portal/src/api/socket.ts` | WebSocket client — fix applied here |
| `ElevatedIQ-Mono-Repo/apps/portal/src/api/client.ts` | REST polling client — future improvement needed |
| `ElevatedIQ-Mono-Repo/apps/portal/src/App.tsx` | Root component with `useTick` |
| `HAProxy-portal-incident-2026-03-05.md` | Prior HAProxy/TLS incident (separate from this issue) |
| `.local_issues/370-portal-ui-unresponsive.md` | Issue tracker entry |
| `services/eiq-api/README.md` | eiq-api deployment and health-check guidance |
