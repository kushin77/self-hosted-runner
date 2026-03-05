Title: CRITICAL: Staging Cluster API Server Offline (192.168.168.42:6443) (#343)
Status: OPEN
LastUpdated: 2026-03-05T17:52:30Z
Notes:
- API server TCP 6443 connection refused
- Impact: KEDA smoke-test blocked
- Actions for Ops provided: SSH, systemctl start k3s, check logs
- Workaround: run basic runner smoke-test instead
