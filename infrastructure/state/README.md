# infrastructure/state

This directory stores idempotent, immutable state markers used by the master orchestration and consolidated workflows.

Files should be written atomically by workflows and use the naming convention:

  <workflow>-<execution-id>.json

Example content:
{
  "execution_id": "20260308T123456-12345",
  "workflow": "gsm-secrets-sync-rotate",
  "status": "completed",
  "timestamp": "2026-03-08T12:34:56Z"
}

Workflows must check for existing marker files before taking action to ensure idempotency.
