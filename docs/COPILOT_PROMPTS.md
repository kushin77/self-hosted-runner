# Copilot Prompt Guidelines for Sovereign Development

Purpose: Ensure any Copilot or LLM prompt authored for repo automation or developer assistance respects sovereignty.

Rules:
- Always include the environment (e.g., `ENV=prod`, `REGISTRY_URL=https://registry.internal`) in the prompt.
- Never include real secrets, tokens, or credentials in prompts. Use placeholders and instruct to fetch from Vault.
- Prefer internal endpoints and registry URLs; avoid `github.com`, `npmjs.org`, `docker.io` in production prompts unless explicitly allowed.

Template Example:
"""
Context: You are run inside the ElevatedIQ self-hosted environment. Use internal registry `REGISTRY_URL` and secret store `VAULT_ADDR`. Do not suggest or call external SaaS. Use `terraform` and `helm` artifacts from the `deploy/` directory.
Task: [describe task].
"""

Enforcement:
- Add CI checks that scan prompts and automation scripts for disallowed endpoints or hardcoded secrets.
- Document allowed exception process in `docs/SOVEREIGNTY_README.md`.