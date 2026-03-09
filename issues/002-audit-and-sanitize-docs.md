Title: Audit & sanitize repository docs/artifacts for token-like placeholders

Purpose:
- Find and sanitize token-like literals (GH tokens, Vault AppRole IDs, secret IDs, AWS keys) across docs, workflows, scripts, and archived artifacts.

Tasks:
- Run a repo-wide scan for common token patterns and collect findings.
- Group findings into safe-to-ignore (false positives) and actionable redactions.
- Open small Draft issues to redact literal tokens and replace with placeholders.

Deliverables:
- A PR per small redaction and an audit report listing remaining high-risk files.
