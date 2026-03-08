Self-Healing Auto Merge
======================

Risk-based auto-merge manager. Integration adapters should implement the
actual GitHub operations and pass `merge_func`/`rollback_func` callables.

Design goals: idempotent merges, risk tiers, schedule/rollback hooks, and
safe-by-default behavior (CRITICAL requires manual review).
