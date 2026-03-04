---
name: Auto-Fix Common Code Issues
description: Scan PRs and issues for common code issues, suggest fixes
on:
  pull_request:
    types: [opened, synchronize]
  issues:
    types: [opened, labeled]
permissions:
  contents: read
  pull-requests: write
  issues: write
runs-on: elevatediq-runner
concurrency:
  group: auto-fix-${{ github.event.pull_request.number || github.issue.number }}
  cancel-in-progress: true
---

## Task: Analyze Code for Common Issues

You have access to:
- The repository content (full clone)
- Current PR/issue details
- GitHub API via the provided token

**Your job:**

1. **Identify patterns** in the code change or issue description:
   - Missing error handling
   - Unhandled promise rejections
   - TODO/FIXME comments that need fixing
   - Missing JSDoc comments on exported functions
   - Stale test snapshots
   - Unused imports or variables
   - Performance anti-patterns

2. **For each issue found:**
   - Create a concise review comment explaining:
     - What the issue is
     - Why it matters (severity: low/medium/high)
     - Proposed fix with code example
   - Link to documentation if relevant

3. **Tone:** Constructive, educational, not critical.

## Example Output

```
## 🔍 Auto-Fix Suggestion

**Issue:** Unhandled promise rejection in UserService

**File:** `src/services/UserService.ts:45`

**Severity:** High

**Problem:** Async function `fetchUserProfile()` can reject, but caller doesn't have error handling

**Proposed Fix:**
\`\`\`typescript
try {
  const profile = await fetchUserProfile(userId);
  // ...
} catch (error) {
  logger.error('Failed to fetch profile', { userId, error });
  // handle gracefully
}
\`\`\`

---
```

## Implementation Notes

- Use local Ollama model for analysis (no external calls)
- Skip files matching `.gitignore` patterns
- Ignore vendored code (`node_modules/`, `dist/`, etc.)
- Be concise: max 2-3 suggestions per PR
- If no issues found, just react with ✅ emoji

---

## Framework Support

**Current:** TypeScript/JavaScript (via AST parsing)

**Future:** Python, Go, Rust (extend as needed)
