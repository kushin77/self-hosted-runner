# Contributing Guide

## Branch Naming Convention

**Format:** `TYPE/TICKET-description`

**Valid Types:**
- `feature/` - New user-facing features
- `fix/` - Bug fixes
- `docs/` - Documentation
- `refactor/` - Code restructuring
- `perf/` - Performance improvements
- `ci/` - CI/CD changes
- `test/` - Test additions
- `chore/` - Maintenance
- `security/` - Security patches

**Examples:**
```
✅ feature/INFRA-401-oauth2-integration
✅ fix/AUTH-523-session-timeout
✅ docs/improving-readme
✅ security/CVE-2026-0001-sanitize-input

❌ feature (missing ticket)
❌ INFRA-401 (missing type)
❌ feature_oauth (underscore wrong)
```

## Commit Requirements

1. **Conventional Format:** `TYPE(scope): description`
   - Types: feat, fix, docs, refactor, perf, ci, test, chore, security
   - Max 72 characters
   - Link to ticket/issue

2. **Signed Commits:** All commits must be GPG/SSH signed
   ```bash
   git commit -S -m "feature: add new feature"
   ```

3. **Single Logical Unit:** One feature/fix per commit
   - Max 500 lines per commit
   - Atomic changes only

## PR Requirements

- [ ] Branch follows naming convention
- [ ] Commit messages are conventional
- [ ] All commits are signed
- [ ] All tests passing
- [ ] Test coverage ≥ 85%
- [ ] PR description includes issue link
- [ ] At least 1 code review approval
- [ ] CODEOWNERS reviewed (if applicable)

## Merge Strategy

- **Squash merge only** (clean history)
- Delete branch after merge (automatic)
- Tag releases with semantic versioning

## Questions?

See [100X_GIT_HYGIENE_ENHANCEMENT_ROADMAP.md](../100X_GIT_HYGIENE_ENHANCEMENT_ROADMAP.md)
