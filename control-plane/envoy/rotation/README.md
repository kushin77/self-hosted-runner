# Certificate Rotation for Envoy via Vault Agent

This directory documents how the Vault Agent sidecar will keep certificates refreshed for Envoy.

Behavior:
- Vault Agent will render templates defined in the ConfigMap into `/etc/envoy/tls`.
- Templates call `pki/issue/control-plane-role` with `ttl=72h`; Vault Agent will refresh before expiry.
- When new certs are written to disk, a simple mechanism (e.g., lifecycle handler or sidecar signal) should cause Envoy to reload.

Recommendations:
- Use Vault Agent's `exec` option or an envoy health-check wrapper to gracefully reload envoy on cert refresh.
- For Kubernetes prefer using the Vault CSI provider or the Vault Agent Injector for production-grade rotation and permissions.
