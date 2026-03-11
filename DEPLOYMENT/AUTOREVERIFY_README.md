# Automated Re-Verification

This documents the automated re-verification service and how to enable it on the management host.

Steps for Ops:

1. Install the script to `/usr/local/bin/auto_reverify.sh` and make executable:

```sh
sudo cp scripts/ops/auto_reverify.sh /usr/local/bin/auto_reverify.sh
sudo chown root:root /usr/local/bin/auto_reverify.sh
sudo chmod 0755 /usr/local/bin/auto_reverify.sh
```

2. Copy the systemd service and timer to `/etc/systemd/system/` and update the ExecStart line with the correct `--host`, `--s3-bucket`, and `--github-token` values (or leave `--dry-run` to test):

```sh
sudo cp scripts/ops/auto_reverify.service /etc/systemd/system/auto_reverify.service
sudo cp scripts/ops/auto_reverify.timer /etc/systemd/system/auto_reverify.timer
sudo systemctl daemon-reload
sudo systemctl enable --now auto_reverify.timer
```

3. Secrets: ensure the verifier SSH private key is stored in the approved secret store (GSM/Vault/KMS) and the management host has read access using the same role used by `fetch_credentials.sh`.

4. Confirm runs via logs:

```sh
journalctl -u auto_reverify.service -f
```
