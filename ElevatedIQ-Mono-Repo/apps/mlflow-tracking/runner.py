"""[PHASE 7.0] MLflow Experiment Runner
Orchestrates ML experiments with centralized tracking and artifact management.

NIST Compliance:
  - CA-7: Continuous Monitoring (Experiment orchestration)
  - SI-2: Integrity (Model versioning)
  - AU-2: Audit (Experiment metadata)
"""

import json
import logging
from dataclasses import asdict, dataclass
from datetime import datetime
from typing import Any

import mlflow

from apps.mlflow_tracking.config import get_mlflow_config

logger = logging.getLogger("mlflow.runner")


# ============================================================================
# Data Models
# ============================================================================


@dataclass
class ExperimentConfig:
    """Configuration for a single ML experiment."""

    experiment_name: str
    run_name: str
    model_type: str  # ddpg, ppo, dqn, etc.
    training_dataset_size: int
    feature_count: int
    batch_size: int
    learning_rate: float
    epochs: int
    validation_split: float = 0.2
    random_seed: int = 42
    tags: dict[str, str] | None = None

    def to_dict(self) -> dict[str, Any]:
        """Convert to dictionary for logging."""
        return asdict(self)


@dataclass
class ExperimentMetrics:
    """Metrics recorded during training."""

    epoch: int
    train_loss: float
    val_loss: float
    train_accuracy: float
    val_accuracy: float
    learning_rate: float
    timestamp: str = None

    def __post_init__(self):
        if self.timestamp is None:
            self.timestamp = datetime.now().isoformat()

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


# ============================================================================
# Experiment Runner
# ============================================================================


class MLflowExperimentRunner:
    """Orchestrates ML experiments with MLflow tracking."""

    def __init__(self):
        """Initialize experiment runner."""
        self.config = get_mlflow_config()
        self.current_run = None
        self.metrics_history = []

    def run_experiment(
        self,
        config: ExperimentConfig,
        training_func: callable,
    ) -> dict[str, Any]:
        """Execute a tracked ML experiment.

        Args:
            config: ExperimentConfig with hyperparameters
            training_func: Callable that performs training and returns metrics
                          Expected signature: training_func(config) -> dict

        Returns:
            Dict with run_id, status, final_metrics

        """
        try:
            # Start MLflow run
            self.current_run = self.config.start_run(
                experiment_name=config.experiment_name,
                run_name=config.run_name,
                tags=config.tags or {},
                params={
                    "model_type": config.model_type,
                    "batch_size": config.batch_size,
                    "learning_rate": config.learning_rate,
                    "epochs": config.epochs,
                },
            )

            logger.info(f"🚀 Started MLflow run: {self.current_run.info.run_id}")

            # Log experiment configuration
            config_dict = config.to_dict()
            config_json = json.dumps(config_dict, indent=2, default=str)
            mlflow.log_text(config_json, artifact_file="experiment_config.json")

            # Execute training function
            logger.info("🔄 Executing training function...")
            metrics = training_func(config)

            # Log final metrics
            if isinstance(metrics, dict):
                self.config.log_model_metrics(metrics)
                logger.info(f"✅ Logged metrics: {list(metrics.keys())}")

            # Return run summary
            result = {
                "run_id": self.current_run.info.run_id,
                "status": "FINISHED",
                "experiment_id": self.current_run.info.experiment_id,
                "final_metrics": metrics,
            }

            logger.info(f"✅ Experiment completed: {result['run_id']}")
            return result

        except Exception as e:
            logger.error(f"❌ Experiment failed: {e}", exc_info=True)
            self.config.end_run(status="FAILED")
            return {
                "status": "FAILED",
                "error": str(e),
            }
        finally:
            if self.current_run:
                self.config.end_run()

    def compare_experiments(
        self,
        experiment_names: list,
    ) -> dict[str, Any]:
        """Compare multiple experiments.

        Args:
            experiment_names: List of experiment names to compare

        Returns:
            Comparison dataframe and statistics

        """
        client = self.config.client
        comparison = {
            "experiments": {},
            "best_run": None,
            "best_metric": None,
        }

        for exp_name in experiment_names:
            exp = client.get_experiment_by_name(exp_name)
            if exp is None:
                logger.warning(f"Experiment not found: {exp_name}")
                continue

            runs = client.search_runs(
                experiment_ids=[exp.experiment_id],
                order_by=["metrics.val_accuracy DESC"],
                max_results=1,
            )

            if runs:
                best_run = runs[0]
                comparison["experiments"][exp_name] = {
                    "run_id": best_run.info.run_id,
                    "metrics": best_run.data.metrics,
                    "params": best_run.data.params,
                }

                if (
                    comparison["best_metric"] is None
                    or best_run.data.metrics.get("val_accuracy", 0)
                    > comparison["best_metric"]
                ):
                    comparison["best_run"] = exp_name
                    comparison["best_metric"] = best_run.data.metrics.get(
                        "val_accuracy"
                    )

        return comparison


# ============================================================================
# Singleton Instance
# ============================================================================

_runner = None


def get_runner() -> MLflowExperimentRunner:
    """Get or initialize experiment runner."""
    global _runner
    if _runner is None:
        _runner = MLflowExperimentRunner()
    return _runner
