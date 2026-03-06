Title: Remove committed test logs and ignore artifact log directories

Purpose:
- Remove committed test log artifacts that contain environment-specific token-like lines and ensure artifact log directories are ignored going forward.

Tasks:
- Remove `artifacts/test-logs/*` from the git index (do not delete from disk if needed for local debug).
- Add `artifacts/test-logs/` to `.gitignore`.
- Re-run the repo test suite to confirm the "No hardcoded credentials" check passes.

Notes:
- If any artifacts need to be preserved, move them to a secure storage outside the repo before removal.
