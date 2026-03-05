KEDA autoscaling scaffolding

This directory contains example manifests and notes for integrating KEDA-based autoscaling for GitHub runner pools.

Usage:

- `scaledobject-example.yaml` shows a sample `ScaledObject` that can be wired to a `Deployment` and a `Trigger` (e.g., Prometheus or queue length).
- This is a scaffold for teams to adapt based on their metrics and event sources.

Important:

- KEDA must be installed in the target cluster. See https://keda.sh for installation instructions.
- Autoscaling decisions for runner pools should be reviewed by platform/security teams before production rollout.
