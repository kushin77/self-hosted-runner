# History Purge & Credential Rotation Audit — 2026-03-13

## Summary
- Action: Force-pushed `remediation/clean-main` -> `main` to purge sensitive history.
- Backup: Tag created `backup/main-before-history-purge-20260313T0042Z` pointing to previous `main` SHA.
- Credentials rotated manually via Cloud Build (multiple runs).
- Vault rotation: SKIPPED (Vault host unresolved: `vault.internal`).

## Timeline (UTC)
- 2026-03-13T00:42:00Z — Backup tag created: `backup/main-before-history-purge-20260313T0042Z`.
- 2026-03-13T00:44:00Z — Force-pushed `remediation/clean-main` to `main` (history rewrite).
- 2026-03-13T00:30:08Z — First automated rotation (build `9d6227d2`) succeeded.
- 2026-03-13T00:29:54Z — Manual rotation (build `0c5fa6ee`) succeeded.
- 2026-03-13T00:47:51Z — Manual rotation (build `ed176312`) succeeded; created new secret versions.

## Secrets (latest versions)
- `github-token`: versions 28 (2026-03-13T00:47:51Z), 27 (2026-03-13T00:30:30Z), 26 (2026-03-13T00:00:39Z)
- `aws-access-key-id`: versions 17 (2026-03-13T00:47:54Z), 16 (2026-03-13T00:30:33Z), 15 (2026-03-13T00:00:42Z)
- `aws-secret-access-key`: versions 17 (2026-03-13T00:47:57Z), 16 (2026-03-13T00:30:36Z), 15 (2026-03-13T00:00:44Z)
- `VAULT_ADDR`: last updated 2026-03-12T23:32:06Z (test endpoint)
- `VAULT_TOKEN`: last updated 2026-03-12T23:29:17Z (test token)

## Verification Notes
- All Cloud Build runs completed successfully for rotation steps (non-Vault parts).
- Audit trail entry appended to `audit-trail.jsonl` and committed.
- Post-merge production verification script executed (`scripts/ops/production-verification.sh --quick`).

## Outstanding Actions
1. Provide real `VAULT_ADDR` and `VAULT_TOKEN` to enable Vault AppRole rotation.
2. Run full verification smoke tests across downstream services (I will run these now).
3. Notify repository consumers of history rewrite; rotate any external credentials that remain exposed.

## Contact
- Performed by: automation agent (actions performed on behalf of repository maintainers)
- Timestamp: 2026-03-13T00:49:31Z

---

Appendix: audit entries and verification outputs are stored in `reports/` and `audit-trail.jsonl` in the repository.
