---
name: Dependency Security Audit
description: Weekly scan for vulnerable or outdated dependencies
on:
  schedule:
    - cron: '0 0 * * MON'
  workflow_dispatch:
permissions:
  contents: write
  pull-requests: write
  issues: write
runs-on: elevatediq-runner
---

## Task: Audit Project Dependencies

Scan all package.json and requirements.txt files for:

1. **Security Vulnerabilities**
   - Known CVEs in current versions
   - Outdated packages with patches available
   - Deprecated libraries

2. **Update Opportunities**
   - Major version bumps with breaking changes
   - Minor updates that are safe
   - Patch-only updates

3. **Health Indicators**
   - Unmaintained packages (no commits in 2+ years)
   - Low community adoption
   - License compliance issues

---

## Output

For each finding, create an issue (not PR) with:

**Critical (immediate action):**
- Description of vulnerability
- Recommended fix version
- Links to advisory

**High (next sprint):**
- Reason for update
- Compatibility notes
- Testing recommendations

**Medium/Low (backlog):**
- Summary of changes
- No immediate action needed
- Include for awareness

---

## Integration Points

- Slack notification for critical findings
- Link from Portal dashboard
- Optional: auto-create pull request for patch updates
