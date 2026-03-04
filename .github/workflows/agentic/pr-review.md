---
name: PR Review Checklist
description: Automated review for common PR issues
on:
  pull_request:
    types: [opened, synchronize]
permissions:
  pull-requests: write
runs-on: elevatediq-runner
---

## Task: Run PR Quality Checklist

Review this PR systematically for:

### 1. **Description & Scope**
- Is the PR description clear?
- Is the scope reasonable (not too large)?
- Are related issues linked?

### 2. **Code Quality**
- Any obvious logic errors?
- Edge cases handled?
- Code style consistent with repo?

### 3. **Testing**
- Are new tests added?
- Do existing tests still pass?
- Coverage maintained or improved?

### 4. **Documentation**
- README updated if needed?
- Comments on complex logic?
- API docs updated?

### 5. **Dependencies**
- New dependencies? Are they necessary?
- Supply chain risk acceptable?

---

## Output Format

Write a single summary comment listing:
- ✅ Passed checks (be specific)
- ⚠️ Items to review
- 🔴 Blockers

Example:
```
## PR Review Summary

✅ **Passed:**
- Clear description with linked issue
- New test coverage for feature
- No major security concerns

⚠️ **Review Items:**
- Database migration needs peer review
- Performance impact for large datasets unclear

🔴 **Blockers:**
- Missing changelog entry
```
