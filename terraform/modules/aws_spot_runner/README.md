# AWS EC2 Spot Runner module

This module provisions an AWS Auto Scaling Group using Spot Instances with a
fallback to On-Demand capacity. It's a scaffold for runner pool integration
and should be extended with launch templates, lifecycle hooks, and termination
handling.

See `examples/` for usage.
