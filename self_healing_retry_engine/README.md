<<<<<<< HEAD
# Self-Healing Retry Engine

Lightweight scaffold for the RetryEngine (P0).

- `retry.py`: `RetryEngine` with exponential backoff, circuit breaker stub, and classifier placeholder.
- `test_retry.py`: basic pytest tests.
=======
Self-Healing Retry Engine
=========================

Small, testable retry engine with exponential backoff, jitter and a
lightweight circuit breaker. Designed to be idempotent and safe for
automation use. Secrets/credentials are not stored here; integration points
for GSM/VAULT/KMS should be added by the deployment layer.

Key features:
- Exponential backoff with jitter
- Pluggable transient/permanent error classifier
- Circuit breaker with reset timeout
>>>>>>> 2e570800c (feat(retry): implement RetryEngine (backoff + circuit breaker) + tests)
