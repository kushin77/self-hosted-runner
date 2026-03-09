# AWS EC2 Spot Instance Market Sizing Guide

## Overview

This guide describes how to size and manage AWS EC2 Spot Instance capacity for the self-hosted runner infrastructure, including market selection, allocation strategies, and interruption handling.

## Spot Instance Sizing Principles

### 1. Capacity Planning

First, determine your total runner capacity needs:

```
Total Capacity = Peak Concurrent Jobs / Avg Jobs per Runner
```

**Example**: 
- 100 peak concurrent jobs
- 5 jobs per runner on average
- Required capacity: 20 runners

### 2. Spot vs On-Demand Mix

Recommended allocation strategies:

| Workload Type | Spot % | On-Demand % | Rationale |
|---|---|---|---|
| Dev/Test | 100% | 0% | Non-critical, interruptions acceptable |
| CI/CD (lint/unit tests) | 80% | 20% | Low interrupt sensitivity, fallback for critical |
| Integration tests | 60% | 40% | Moderate sensitivity to interruptions |
| Production builds | 30% | 70% | High availability required |
| Release builds | 0% | 100% | Zero tolerance for interruptions |

### 3. Instance Type Selection

**Criteria for selecting instance types:**

1. **CPU requirement**: Minimum cores needed for workload (GitHub Actions = 2+ cores)
2. **Memory requirement**: Minimum RAM (4GB for most CI/CD workloads)
3. **Spot availability**: Choose types with high availability (t2, t3, m5, c5)
4. **Cost**: Balance between price and performance
5. **Interruption rate**: Historical interruption rates < 2% for production

**Recommended instance types:**

| Use Case | Instance Type | vCPU | Memory | Hourly Cost (Spot/OD) | Notes |
|---|---|---|---|---|---|
| Dev/Test | t2.small | 1 | 2 GB | $0.007/$0.025 | Good entry point |
| General CI/CD | t3.medium | 2 | 4 GB | $0.0125/$0.0416 | Most common choice |
| Build jobs | m5.large | 2 | 8 GB | $0.0288/$0.096 | Additional memory |
| Compute-heavy | c5.large | 2 | 4 GB | $0.0255/$0.085 | Optimized for CPU |

### 4. Regional Considerations

Spot pricing and availability vary by region:

**Best regions for spot savings:**
- us-east-1: ~70% average discount
- us-west-2: ~72% average discount
- eu-west-1: ~70% average discount

**Tips for multi-region:**
- Use capacity-optimized allocation strategy (default in our module)
- Monitor interruption rates per region
- Implement fallback to on-demand in higher cost regions

## Sizing Calculation Examples

### Scenario 1: Small Development Team

**Requirements:**
- 20 concurrent CI jobs
- Average 2 jobs per runner
- Willing to accept occasional delays
- Development/test workloads only

**Calculation:**
```
Runners needed: 20 / 2 = 10 runners
Instance type: t3.small (adequate for most tests)
Spot allocation: 100%
Cost: 10 × $0.0062/hr × 730 hrs/month ≈ $45/month
```

### Scenario 2: Medium Production Environment

**Requirements:**
- 50 concurrent CI jobs
- Average 4 jobs per runner
- Some production builds (need reliability)
- Mix of workload types

**Calculation:**
```
Runners needed: 50 / 4 = 12.5 → 13 runners

Allocation:
- Dev/test: 4 runners spot only
- CI build: 6 runners (5 spot + 1 on-demand)
- Production: 3 runners on-demand only

Cost breakdown (monthly):
- Dev/test spot (t3.small): 4 × $0.0062 × 730 ≈ $18
- CI spot (t3.medium): 5 × $0.0125 × 730 ≈ $46
- CI on-demand (t3.medium): 1 × $0.0416 × 730 ≈ $30
- Production on-demand (m5.large): 3 × $0.096 × 730 ≈ $210
Total: ~$304/month
```

### Scenario 3: Large Enterprise Deployment

**Requirements:**
- 200 concurrent CI jobs
- Average 5 jobs per runner
- High reliability SLA (99.5% availability)
- 24/7 operations

**Calculation:**
```
Runners needed: 200 / 5 = 40 runners

Allocation for 99.5% SLA:
- Spot pool: 28 runners (t3.medium) - 70%
- On-demand pool: 12 runners (t3.medium) - 30%

Cost breakdown (monthly):
- Spot (t3.medium): 28 × $0.0125 × 730 ≈ $256
- On-demand (t3.medium): 12 × $0.0416 × 730 ≈ $365
Total: ~$621/month

Interruption handling:
- Average spot interruptions: 2% of 28 = 0.56 runners/day
- On-demand capacity absorbs interruptions
- SLA math: (12 × 100%) + (28 × 98%) = 39.44/40 = 98.6% → 99.5% with multi-AZ failover
```

## Spot Interruption Handling

### Interruption Rates by Instance Family

**Historical data (AWS averages):**
- t2: 0.5-1.5% interruption rate
- t3: 0.3-1.0% interruption rate
- m5: 0.5-1.2% interruption rate
- c5: 0.4-1.0% interruption rate

### Lifecycle Hook Implementation

Our Terraform module includes automatic interruption handling:

```hcl
# Automatically notifies Lambda consumer 2 minutes before termination
aws_autoscaling_lifecycle_hook {
  heartbeat_timeout = 300  # Gives graceful shutdown 5 minutes
  default_result    = "CONTINUE"  # Proceed with termination if no response
}

# Lambda drains running jobs before instance termination
# SQS queue tracks all lifecycle events
```

### Graceful Shutdown Flow

1. **Interruption signal received** (2 minutes warning)
2. **Lifecycle hook triggered** → publishes to SNS
3. **Lambda consumer receives notification** via SQS
4. **Webhook issued to runner** → drain active jobs
5. **Runner in "offline" mode but finishes current job**
6. **After timeout or job completion** → instance terminates
7. **Replacement instance provisioned** by ASG

## Cost Optimization Strategies

### 1. Instance Right-Sizing

```bash
# Analyze actual resource usage
# If consistent <50% CPU/Memory → downsize
Example: t3.large (underutilized) → t3.medium (30% savings)
```

### 2. Spot Allocation Strategy

```hcl
# Capacity-optimized (default in our module)
# Distributes across instance types to reduce interruption rate
spot_allocation_strategy = "capacity-optimized"
```

### 3. Mixed Instances Policy

```hcl
# Balance cost and availability
on_demand_percentage_above_base_capacity = 20
spot_allocation_strategy = "capacity-optimized"

# 80% spot, 20% on-demand ensures stable baseline
```

### 4. Scheduled Scaling

For predictable workloads:

```python
# Peak hours: 9 AM - 6 PM = max capacity
# Off-peak: scaled down 50%
# Saves ~30% monthly for typical patterns
```

### 5. Reserved Instances (Optional)

For on-demand baseline:

```
On-demand cost: 12 runners × $0.0416/hr × 730 = $365/month

With 1-year RI commitment:
RI cost: 12 runners × $0.025/hr × 730 = $219/month
Savings: $146/month (40% discount)
```

## Monitoring and Optimization

### Key Metrics

```
1. Interruption rate: Target < 2%
2. Job success rate: Track correlation with spot usage
3. Cost per job: Monitor trend over time
4. Instance utilization: CPU, memory, disk
5. Queue depth: Jobs waiting for runners
```

### Autoscaling Rules

```hcl
# Scale up if queue depth > 50 jobs
# Scale down if queue depth < 10 jobs
# Target group size balanced across spot/on-demand
```

### Cost Monitoring

```bash
# Monthly cost trend
aws ce get-cost-and-usage \
  --time-period Start=2026-03-01,End=2026-03-31 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=INSTANCE_TYPE
```

## Troubleshooting

### Issue: High Interruption Rate (>5%)

**Solutions:**
1. Add on-demand capacity (increase on_demand_percentage)
2. Switch to different instance types with lower interruption
3. Consider dedicated instance pool

### Issue: Jobs Failing During Interruption

**Check:**
1. Verify lifecycle hook timeout (should be 300+ seconds)
2. Ensure drain webhook is configured and responding
3. Check Lambda consumer is running and processing messages

### Issue: Higher Than Expected Costs

**Investigate:**
1. Confirm spot allocation is actually being used (check ASG)
2. Verify instance types match configuration
3. Check for on-demand fallback overrides
4. Review regional pricing differences

## References

- [AWS Spot Instance Documentation](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-spot-instances.html)
- [Spot Instance Interruption Notices](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-interruptions.html)
- [EC2 Instance Types](https://aws.amazon.com/ec2/instance-types/)
- [Pricing Calculator](https://calculator.aws/)

## Terraform Module Reference

See `terraform/modules/aws_spot_runner/README.md` for:
- Module variables and outputs
- Lifecycle hook configuration
- Lambda handler setup
- Security group configuration
