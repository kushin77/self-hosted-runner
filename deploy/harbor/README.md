# Harbor Helm chart (hardened scaffold)

This scaffold provides a minimal Harbor deployment (core + portal) with persistence and placeholders for DB, Redis, and Trivy scanner.

For production use, prefer the official Harbor Helm chart and configure:
- External PostgreSQL database
- Redis cache
- Trivy scanner integration
- TLS and ingress
- Persistent volumes and backups

This chart is intended as a starting point for integration testing and will be hardened in follow-up PRs.
