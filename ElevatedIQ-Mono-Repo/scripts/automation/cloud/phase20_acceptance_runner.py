from __future__ import annotations

import json
from datetime import UTC, datetime
from pathlib import Path
from typing import Any


def _latest(path: Path, pattern: str) -> Path | None:
    candidates = sorted(path.glob(pattern))
    return candidates[-1] if candidates else None


def _load(path: Path | None, default: dict[str, Any]) -> dict[str, Any]:
    if path is None or not path.exists():
        return default
    return json.loads(path.read_text(encoding="utf-8"))


def run_acceptance(root: Path) -> Path:
    """run_acceptance function."""
    dry_run = _load(_latest(root / "reports" / "dry-run", "dry-run-*.json"), {"per_target": {}, "score": 0})
    forecast = _load(root / "reports" / "finops" / "finops-forecast-latest.json", {"budget_gate": "FAIL"})
    failover = _load(
        root / "reports" / "failover" / "multi-region-failover-plan-latest.json",
        {"primary": None, "failover_order": []},
    )
    metrics = _load(
        root / "reports" / "dry-run" / "metrics" / "summary" / "metrics-report-latest.json",
        {"memory_mb": 9999, "target_count": 0},
    )

    targets = dry_run.get("per_target", {})
    e2e_ok = bool(targets) and all(details.get("health") == "pass" for details in targets.values())
    perf_ok = float(metrics.get("memory_mb", 9999)) < 500 and int(metrics.get("target_count", 0)) >= 1000
    finops_ok = forecast.get("budget_gate") == "PASS"
    forecast_total = float(forecast.get("monthly_total_forecast", 0.0))
    trailing_actual = float(forecast.get("trailing_3m_monthly_actual", 0.0))
    accuracy_ok = trailing_actual > 0 and abs(forecast_total - trailing_actual) / trailing_actual <= 0.05
    failover_ok = failover.get("primary") is not None and isinstance(failover.get("failover_order"), list)

    report = {
        "timestamp_utc": datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "checks": {
            "e2e_dry_run": "PASS" if e2e_ok else "FAIL",
            "metrics_capacity": "PASS" if perf_ok else "FAIL",
            "finops_accuracy_gate": "PASS" if finops_ok and accuracy_ok else "FAIL",
            "failover_execute_rollback": "PASS" if failover_ok else "FAIL",
        },
        "go_live_ready": e2e_ok and perf_ok and finops_ok and accuracy_ok and failover_ok,
        "signoff": {
            "sre": "PENDING",
            "secops": "PENDING",
        },
    }

    out_dir = root / "reports" / "acceptance"
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / "phase20-go-live-readiness-latest.json"
    out_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return out_path


if __name__ == "__main__":
    repository_root = Path(__file__).resolve().parents[3]
    print(run_acceptance(repository_root))
