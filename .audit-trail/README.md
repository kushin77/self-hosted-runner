# Immutable Audit Trail

This directory contains append-only logs of all git hygiene operations:

- `branch-operations.log` - All branch creates/deletes/protection changes
- `pr-reviews.log` - All PR approvals, reviews, merges
- `commit-violations.log` - All commit policy violations
- `secret-scan.log` - All secret detection events
- `compliance.log` - Overall compliance scoring history

**All logs are append-only and cryptographically signed.**
