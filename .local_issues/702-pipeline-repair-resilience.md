Title: Add Pipeline Repair service resilience (#702)

Summary:
- Implement retry-with-jitter, capped exponential backoff, and escalation when max retries reached.
- Make retry parameters configurable via RepairService config (maxAttempts, baseDelayMs, maxDelayMs, jitter).
- Add circuit-breaker or escalation policy if needed to avoid thrashing (next iteration).

Changes made:
- Updated `services/pipeline-repair/lib/repair-service.js` to pass config into strategies.
- Updated `services/pipeline-repair/strategies/retry.js` to support options: `maxAttempts`, `baseDelayMs`, `maxDelayMs`, and `jitter`; added capped exponential backoff with jitter and escalation action when max attempts reached.

Testing/Validation:
- Unit tests to add: validate backoff calculation, jitter bounds, and ESCALATE action after max attempts.
- Manual validation: run `node services/pipeline-repair/lib/repair-service.js` to inspect sample run output.

Next steps:
- Add unit tests for `retry` strategy under `services/pipeline-repair/tests/`.
- Consider adding a small circuit-breaker strategy to short-circuit repeated failures across many events.
- Wire configurable defaults from service config (env / config file) in production deployments.

References:
- Related repo issues: #702
- Files changed: `services/pipeline-repair/lib/repair-service.js`, `services/pipeline-repair/strategies/retry.js`
