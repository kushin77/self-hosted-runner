Title: Portal UI Unresponsive — WebSocket reconnect storm & polling overlap (#370)
Status: OPEN
LastUpdated: 2026-03-06T00:28:50Z
Notes:
- Symptom: portal dashboard freezes / becomes unresponsive after backend restarts or brief network interruption
- Root causes identified in ElevatedIQ-Mono-Repo/apps/portal/src/api/socket.ts:
    1. reconnectionAttempts set to Infinity — socket storms the server with retry requests on disconnect
    2. useMetrics polling (5 s interval) does not guard against concurrent in-flight requests, causing fetch pile-up
    3. useTick(2500) in App.tsx triggers component-tree re-renders every 2.5 s independent of data readiness
- Server-side: eiq-api (managed-auth on port 9090) logs show burst of socket.io handshakes during recovery window
- Investigation log: docs/PORTAL_UI_UNRESPONSIVE_INVESTIGATION.md
- Fix applied: socket.ts capped to reconnectionAttempts: 10 and exposed socketReconnectFailed flag to UI via Zustand store
- Next steps:
    1. Ops: verify eiq-api health after restart (curl http://localhost:9090/health)
    2. Frontend: add React error boundary around Dashboard to prevent full-page freeze
    3. Monitoring: add Prometheus alert for socket.io handshake rate spike (> 20/min per client)
