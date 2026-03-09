Prompt Library — Organize Milestones

This folder contains reusable prompts and helpers for organizing GitHub issues into milestones.

- `organize-milestones.md` — Reusable assistant prompt to discover open issues, propose milestones, and assign issues in safe, batched operations.

Usage
- Read the prompt to understand the heuristics and required permissions.
- Use the script `scripts/organize_milestones.sh` to preview or apply the milestone creation and assignment using the `gh` CLI.

Permissions
- The script and prompt assume the runner has `gh` authenticated with repo scope.

See also: `scripts/organize_milestones.sh`
