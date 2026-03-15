# [100X-03] Standardize env vars and templates

## Objective
Ensure env-driven configuration and template-based generation across the stack.

## Acceptance Criteria
- Missing env vars fail fast\n- Templates generate config\n- No hardcoded domain drift

## Notes
- Domain standard: elevatediq.ai
- Naming standard: elevatediq-<service>-<env>
- Deployment must be idempotent and fully script-driven
