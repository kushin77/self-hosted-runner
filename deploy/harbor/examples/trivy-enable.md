# Trivy integration for Harbor

To enable Trivy scanning for Harbor in this scaffold, follow the example steps below.

1) Enable the scanner in chart values (set `trivy.enabled=true`).

2) Deploy a Trivy scanner service (e.g., `trivy-adapter`) and point Harbor to the scanner endpoint via Helm values.

3) Configure scan policies in Harbor and configure webhooks to send results to the control plane aggregation endpoint.

This document is a placeholder with recommended steps; follow-up PR will provide concrete helm manifests and example webhook consumer.
