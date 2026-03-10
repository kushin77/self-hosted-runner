NexusShield systemd units
=========================

This directory contains example systemd unit and timer files to schedule automated credential rotation.

Install (run as root):

1. Copy units to `/etc/systemd/system/`:

```bash
sudo cp nexusshield-credential-rotation.service /etc/systemd/system/
sudo cp nexusshield-credential-rotation.timer /etc/systemd/system/
```

2. Reload systemd, enable and start the timer:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now nexusshield-credential-rotation.timer
```

Notes:
- Ensure the `ops` user exists and has access to the repository path.
- Adjust `ExecStart` to point to your credential backend (GSM/Vault/KMS) as needed.
