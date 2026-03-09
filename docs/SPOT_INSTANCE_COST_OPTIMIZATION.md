# AWS EC2 Spot Instance Cost Optimization Guide

## Executive Summary

By using AWS EC2 Spot instances for CI/CD workloads, organizations typically save **60-80%** on compute costs compared to on-demand instances while maintaining reliability through mixed instance policies and graceful interruption handling.

## Cost Breakdown: Spot vs On-Demand

### Monthly Cost Comparison (10 Runners)

```
Instance Type: t3.medium

On-Demand Only:
  10 runners × $0.0416/hr × 730 hours/month = $304/month

80% Spot + 20% On-Demand:
  8 runners × $0.0125/hr × 730 = $73
  2 runners × $0.0416/hr × 730 = $61
  Total = $134/month

Savings: $170/month (56% reduction)
Annual: $2,040 savings
```

### Scaling Impact

| Runners | On-Demand | 80/20 Mix | 100% Spot | Yearly Savings |
|---------|-----------|----------|-----------|---|
| 10 | $304/mo | $134/mo | $91/mo | $2,040 |
| 25 | $760/mo | $335/mo | $228/mo | $5,100 |
| 50 | $1,520/mo | $670/mo | $456/mo | $10,200 |
| 100 | $3,040/mo | $1,340/mo | $912/mo | $20,400 |

## Cost Optimization Strategies

### 1. Right-Sizing Instances

**Problem**: Oversized runners waste resources and increase costs.

**Solution**: Monitor actual usage and adjust instance types:

```bash
# Check average CPU utilization
SELECT instance_type, AVG(cpu_utilization) as avg_cpu
FROM CloudWatch
WHERE resource_type = 'runner'
GROUP BY instance_type

# If avg_cpu < 30% for 2+ weeks → downsize
Example: t3.large → t3.medium = 50% cost savings
```

**Impact**: 10-20% cost reduction through right-sizing

### 2. Intelligent Instance Selection

**Recommendation Matrix**:

| Workload | Instance Type | Cost/hr | Performance | Recommendation |
|----------|---------------|---------|-------------|---|
| Lint/unit tests | t2.small | $0.007 | Adequate | ✓ Use |
| Build jobs | t3.medium | $0.0125 | Good | ✓ Primary choice |
| Integration tests | m5.large | $0.0288 | Excellent | ~ Consider for specific jobs |
| Docker builds | c5.large | $0.0255 | CPU optimized | ~ Use for build-heavy jobs |

**Strategy**: Use job labels to route workloads to appropriate instance types

```yaml
runs-on:
  - self-hosted
  - docker-builder  # Routes to c5.large spot instances
```

**Impact**: 15-25% savings through workload optimization

### 3. Allocation Strategy: Spot/On-Demand Mix

**Static Mix Strategy**: Balances cost and reliability

```
Development/Test:
  Spot: 100% (pure cost optimization, high interrupt tolerance)
  
Standard CI:
  Spot: 80%, On-Demand: 20% (good balance)
  
Production Builds:
  Spot: 50%, On-Demand: 50% (high reliability)
  
Release/Production:
  Spot: 0%, On-Demand: 100% (zero tolerance)
```

**Dynamic Scaling Strategy**: Adjust based on queue depth

```python
def calculate_spot_percentage(queue_depth):
    if queue_depth < 5:
        return 100  # All spot when queue empty
    elif queue_depth < 20:
        return 80   # Mostly spot
    elif queue_depth < 50:
        return 50   # Balanced
    else:
        return 20   # Mostly on-demand under load
```

**Impact**: 40-60% cost reduction with dynamic strategy

### 4. Multi-Region Arbitrage

**Price Differences Across Regions:**

```
t3.medium hourly spot price comparison:

us-east-1:   $0.0125 (baseline)
us-west-2:   $0.0115 (8% cheaper)
eu-west-1:   $0.0136 (9% more expensive)
```

**Optimization**:
- Prefer us-west-2 over us-east-1 (8% savings)
- Use us-east-1 for lowest latency to GitHub
- Avoid eu-west-1 unless specifically needed

**Impact**: 5-10% additional savings with region optimization

### 5. Reserved Instances for Baseline

**For On-Demand Baseline Capacity:**

```
Without RI:
  2 runners on-demand: 2 × $0.0416/hr × 730 = $61/month

With 1-year RI:
  2 runners on-demand: 2 × $0.025/hr × 730 = $37/month
  
Savings: $24/month = $288/year
ROI: Pay upfront ~$290, save ~$288/year (breakeven)
```

**Recommendation**: Reserve capacity for 20-30% on-demand baseline

**Impact**: 30-40% savings on on-demand costs

### 6. Interruption Minimization

**Problem**: Interruptions can trigger expensive on-demand fallback

**Solutions**:

1. **Capacity-optimized allocation** (default)
   - Distributes across instance types with higher availability
   - Reduces interruption rate by 40-60%

2. **Diversify instance types**
   ```hcl
   allowed_instance_types = ["t3.medium", "t3a.medium", "m5.large", "m6i.large"]
   # Spreads load across types → lower interruption
   ```

3. **Diversify availability zones**
   ```hcl
   subnet_ids = ["subnet-az-1", "subnet-az-2", "subnet-az-3"]
   # 3 AZs reduce interruption impact by 3x
   ```

**Impact**: Prevents 20-30% cost increases from fallback

### 7. Scheduled Scaling

**Pattern**: Most teams have predictable peak hours

```
Weekday Peak:   8 AM - 7 PM (11 hours)
Weekday Off:    7 PM - 8 AM (13 hours)
Weekend:        50% reduced capacity

Strategy:
- Scale up 1 hour before peak
- Scale down gradually after peak
- Maintain small on-demand baseline 24/7
```

**Implementation Example**:

```python
# 40 total runners

# Peak hours (9 AM - 6 PM): Full capacity
PEAK_CAPACITY = 40
PEAK_SPOT_PCT = 80

# Off-peak (7 PM - 8 AM): 50% capacity
OFFPEAK_CAPACITY = 20
OFFPEAK_SPOT_PCT = 100

def calculate_monthly_cost():
    peak_hours = 11 * 5 * 4.3  # weekday peak hours
    offpeak_hours = 13 * 5 * 4.3 + 24 * 8 * 4.3  # weekday off-peak + weekend
    
    peak_cost = (40 * 0.8 * 0.0125 + 40 * 0.2 * 0.0416) * peak_hours
    offpeak_cost = 20 * 0.0125 * offpeak_hours
    
    return peak_cost + offpeak_cost

# ~$200/month for 40 runners vs $304 constant = $1,248/year savings
```

**Impact**: 25-35% cost reduction through scheduled scaling

### 8. Efficient Resource Utilization

Monitor and optimize actual resource usage:

```hcl
# Add monitoring
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  metric_name          = "CPUUtilization"
  threshold            = 80
  alarm_description    = "Alert if runner CPU > 80%"
}

# Identify opportunities to batch jobs or optimize workflows
# Example: Parallel testing reduces runner count needs
```

**Impact**: 10-15% improvement through better scheduling

## Cost Optimization Checklist

- [ ] Spot allocation strategy configured (80/20 or better)
- [ ] Instance types right-sized for actual workloads
- [ ] Capacity-optimized allocation enabled
- [ ] Multi-AZ subnet distribution configured
- [ ] On-demand baseline protected with RIs (optional)
- [ ] Scheduled scaling for predictable periods
- [ ] Lifecycle hooks configured for graceful shutdown
- [ ] Cost monitoring alerts configured
- [ ] Monthly cost trends tracked and analyzed

## Real-World Example: Cost Reduction Implementation

### Current State (Baseline)
```
30 runners, all on-demand (t3.medium)
Cost: 30 × $0.0416/hr × 730 = $912/month ($10,944/year)
```

### Optimization Phase 1: Spot Introduction (Week 1)
```
Configuration: 24 spot (80%) + 6 on-demand (20%)
Cost: (24 × $0.0125 + 6 × $0.0416) × 730 = $401/month
Savings: $511/month = $6,132/year
SLA impact: 2-3% job delays acceptable
```

### Optimization Phase 2: Right-sizing (Week 4)
```
Discover 20% runners under-utilized
Downsize 6 runners from t3.medium to t2.medium
Change config: 20 t2.medium spot + 6 t3.medium spot + 4 t3.medium on-demand
Cost: (20 × $0.0062 + 6 × $0.0125 + 4 × $0.0416) × 730 = $274/month
Savings: $638/month = $7,656/year
```

### Optimization Phase 3: Scheduled Scaling (Week 8)
```
Add scheduled scaling for weekday peaks
Reduce off-peak from 30 to 15 runners
Average capacity: (30 × 11 + 15 × 13) / 24 = 20.625 runners
Estimated cost: $180/month
Savings: $732/month = $8,784/year (76% reduction!)
```

## Monitoring Dashboard

Recommended metrics to track:

```
Priority 1 (Financial):
  - Monthly compute cost
  - Cost per job
  - Cost per GB processed

Priority 2 (Performance):
  - Job success rate
  - Interruption rate (actual vs expected)
  - Queue depth

Priority 3 (Optimization):
  - Spot vs on-demand utilization ratio
  - Instance type distribution
  - Regional distribution of jobs
```

## Continuous Optimization

**Monthly Review Process**:

1. Analyze cost trends
2. Identify high-cost workloads
3. Check interruption rates by instance type
4. Adjust allocation strategies if needed
5. Update forecasts
6. Plan next quarter optimizations

## References

- [AWS Spot Instance Pricing](https://aws.amazon.com/ec2/spot/pricing/)
- [Reserved Instance Pricing](https://aws.amazon.com/ec2/pricing/reserved-instances/)
- [Spot Instance Interruption Rates](https://aws.amazon.com/ec2/spot/interruption-rate/)
- [AWS EC2 Cost Explorer](https://docs.aws.amazon.com/general/latest/gr/cost-management.html)
- [Cost Optimization Best Practices](https://docs.aws.amazon.com/whitepapers/latest/cost-optimization-ec2/)
