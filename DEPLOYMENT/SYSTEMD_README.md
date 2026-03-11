# Systemd Unit and Sample Env for Canonical Secrets

Place the sample env at `/etc/canonical_secrets.env` and the service unit at `/etc/systemd/system/canonical-secrets.service`.

Steps:

1. Copy sample env to host and edit values:

```bash
sudo cp /opt/runner/repo/scripts/ops/sample_canonical_secrets.env /etc/canonical_secrets.env
sudo chown root:root /etc/canonical_secrets.env
sudo chmod 640 /etc/canonical_secrets.env
```

2. Install systemd unit:

```bash
sudo cp /opt/runner/repo/scripts/ops/canonical-secrets.service /etc/systemd/system/canonical-secrets.service
sudo systemctl daemon-reload
sudo systemctl enable --now canonical-secrets-api.service
```

3. Verify service:

```bash
sudo systemctl status canonical-secrets-api.service
journalctl -u canonical-secrets-api.service -n 200
```

Notes:
- The service expects runtime credentials fetched by `scripts/ops/fetch_credentials.sh`.
- Ensure `runner` user exists and has proper permissions for `/opt/runner/repo` and log directories.
