Title: Cleanup VS Code OOM mitigation

Actions performed:
- Deleted all `.terraform` caches across workspace.
- Ran `git gc --prune=now --aggressive`.
- Removed `actions-runner/_work` contents to free space.
- Moved `github.copilot-chat-0.38.1` from `~/.vscode-server/extensions` to `~/.vscode-server/extensions.disabled`.
- Added workspace excludes in `.vscode/settings.json` for `actions-runner`, `terraform`, and `.git/objects`.
- Removed remote VS Code backups where found.
- Temporary: lowered `vm.swappiness` to 10 if permitted.

Notes:
- These changes are reversible; `.terraform` can be reinitialized when needed.
- Recommend testing VS Code remote connection from laptop with `--disable-extensions` first.

