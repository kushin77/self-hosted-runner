# Issue: Azure Tenant API Setup - CLI install failure

Status: blocked

## Summary

Attempted to run `scripts/setup-azure-tenant-api.sh` to create the tenant-wide service principal and store credentials. The setup failed at Azure CLI installation step because `az` is not installed and `apt` failed to update repositories (GCP apt entry returned 404).

## What happened

- `az` was not found on the host.
- The setup script tried to install `az` via the standard apt install path and requested sudo.
- `apt update` failed with: `The repository 'https://packages.cloud.google.com/apt gcloud-cli Release' does not have a Release file.`

This prevented the installation of Azure CLI and blocked the remainder of the setup.

## Impact

- Service principal creation and Key Vault creation cannot proceed until `az` is available and authenticated.

## Recommended Remediation (pick one)

### Option A — Allow interactive installation (preferred)
Run the setup script again and supply your sudo password when prompted. Ensure the host has proper network access and apt sources configured.

```bash
sudo apt update
# Fix any invalid sources.list entries for Google Cloud SDK if present
# Then re-run the interactive setup
bash scripts/setup-azure-tenant-api.sh
```

### Option B — Install `az` for the current user (no sudo)
This attempts a user-local pip install of the Azure CLI and sets PATH for this session. It may not be fully featured but often works for basic CLI tasks.

```bash
python3 -m pip install --upgrade --user pip
python3 -m pip install --user azure-cli
export PATH="$HOME/.local/bin:$PATH"
az --version
```

If `az` installs successfully, re-run the setup script:

```bash
bash scripts/setup-azure-tenant-api.sh
```

### Option C — Fix apt repository issues (if you want system install)
Remove or correct any broken Google Cloud SDK apt source entries in `/etc/apt/sources.list.d/` then:

```bash
sudo apt update
curl -sL https://aka.ms/InstallAzureCliDeb | sudo bash
```

## Next actions mine (won't proceed without `az`):
- Create this local issue record (done).
- Provide a user-level installer script `scripts/ensure-azure-cli.sh` (created).
- Wait for you to: (a) provide sudo, (b) run the user-level install, or (c) update apt sources.

## Audit
Logs: `/tmp/azure-setup-*.log` and `logs/azure-setup/` (check for JSONL audit events)


---
Created: 2026-03-11
