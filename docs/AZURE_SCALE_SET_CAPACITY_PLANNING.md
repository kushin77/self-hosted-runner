# Azure Scale Set Capacity Planning Guide

This guide provides recommendations for planning and managing GitHub Actions runner capacity using Azure Virtual Machine Scale Sets.

## Table of Contents

- [Capacity Planning Fundamentals](#capacity-planning-fundamentals)
- [VM SKU Selection](#vm-sku-selection)
- [Quota and Limits](#quota-and-limits)
- [Autoscaling Configuration](#autoscaling-configuration)
- [Cost Optimization](#cost-optimization)
- [Monitoring and Adjustment](#monitoring-and-adjustment)

---

## Capacity Planning Fundamentals

### Key Metrics

1. **Concurrent Jobs:** Number of workflow jobs that run simultaneously
2. **Job Duration:** Average execution time per workflow job (minutes)
3. **Daily Jobs:** Total number of jobs executed per day
4. **Peak Hours:** Time periods with highest job load

### Capacity Formula

```
Required Instances = (Concurrent Jobs During Peak * 1.2) + Buffer

Example:
- Peak concurrent jobs: 20
- Buffer: 2-3 extra instances
- Required capacity: 20 * 1.2 + 2 = 26 instances
```

### Buffer Strategy

Always add 10-20% buffer capacity to handle:
- Unexpected job spikes
- Maintenance and OS updates
- Instance creation/termination delays

---

## VM SKU Selection

### Recommended SKUs

| SKU | vCPUs | RAM | Use Case | Cost |
|-----|-------|-----|----------|------|
| `Standard_B2s` | 2 | 4GB | Light workloads, testing | $ |
| `Standard_DS2_v2` | 2 | 7GB | General purpose runners | $$ |
| `Standard_D4s_v3` | 4 | 16GB | Medium workloads | $$$ |
| `Standard_D8s_v3` | 8 | 32GB | Heavy compute/builds | $$$$ |
| `Standard_E4s_v3` | 4 | 32GB | Memory-intensive tasks | $$$ |

### Selection Criteria

Choose based on your workflow requirements:

- **CPU-Intensive:** Use D-series or higher (4+ vCPUs)
- **Memory-Intensive:** Use E-series for high RAM
- **General Purpose:** DS2_v2 is cost-effective default
- **Testing/CI:** B2s for light loads or per-job scaling

### Example Configurations

**Lightweight:** Django/Python tests
```hcl
vm_sku = "Standard_DS2_v2"
capacity = 5
enable_autoscaling = true
min_capacity = 2
max_capacity = 15
```

**Heavy:** Docker builds + integration tests
```hcl
vm_sku = "Standard_D4s_v3"
capacity = 10
enable_autoscaling = true
min_capacity = 5
max_capacity = 30
```

**Memory-Intensive:** Large data processing
```hcl
vm_sku = "Standard_E8s_v3"
capacity = 3
enable_autoscaling = true
min_capacity = 2
max_capacity = 8
```

---

## Quota and Limits

### Azure Region Quotas

Azure has regional quotas for vCPU availability. Before deploying, verify quotas:

```bash
# Check available quotas
az compute vm list-usage --location eastus -o table

# Request quota increase if needed
az support tickets create \
  --name "Increase CPU quota for runners" \
  --description "Need additional vCPUS for GitHub Actions runners"
```

### Common Quotas

| Region | Default vCPU Limit | Recommended Increase |
|--------|-------------------|----------------------|
| eastus | 20 | 100+ |
| westus2 | 20 | 100+ |
| eastus2 | 20 | 100+ |
| centralus | 20 | 100+ |

### Managing Quotas

1. **Monitor Usage:** Track current vCPU usage
   ```bash
   az compute vm list-usage --location eastus | grep -i totalcpulimit
   ```

2. **Plan Headroom:** Always have 20% quota buffer
3. **Request Early:** Quota increases take 1-2 business days
4. **Use Multiple Regions:** Distribute load across regions if quota-constrained

---

## Autoscaling Configuration

### Recommended Autoscaling Policies

The module includes a default autoscaling profile:

- **Scale Out Trigger:** CPU > 70% for 5 minutes → Add 1 instance
- **Scale In Trigger:** CPU < 30% for 5 minutes → Remove 1 instance
- **Cooldown:** 5 minutes between scaling events
- **Min/Max:** Configurable based on needs

### Custom Autoscaling Rules

Adjust autoscaling for your workload patterns:

```hcl
# For bursty workloads
min_capacity = 1
max_capacity = 50
enable_autoscaling = true

# For steady workloads
min_capacity = 10
max_capacity = 20
enable_autoscaling = true

# For scheduled workloads (disable autoscaling)
enable_autoscaling = false
capacity = 30  # Fixed capacity for known schedule
```

### Autoscaling Best Practices

1. **Gradual Scaling:** Scale in/out 1-2 instances at a time
2. **Appropriate Cooldown:** 5 minutes prevents flapping
3. **Conservative Thresholds:** Start with 70/30 triggers
4. **Monitor Metrics:** Track actual scaling events and costs
5. **Test Policies:** Validate with non-production workloads first

---

## Cost Optimization

### Calculation Example

**Base Configuration:**
- SKU: Standard_DS2_v2 (2 vCPUs, 7GB RAM)
- Region: East US
- Capacity: 10 instances (minimum)
- Monthly rate: ~$3.29/vCPU/day = ~$197/instance/month

**Monthly Cost Calculation:**
```
Base cost = 10 instances × $197 = $1,970/month
Peak cost = 30 instances × $197 = $5,910/month (with autoscaling peak)
Average cost = ~$3,500/month (estimated with autoscaling)
```

### Cost Optimization Strategies

1. **Reserved Instances (RI):** 30-40% discount for 1-3 year commitments
   ```
   Annual savings: 10 instances × $197/mo × 12 mo × 0.35 = ~$8,250/year
   ```

2. **Spot Instances:** 50-80% discount for non-critical workloads
   - Risk: Can be evicted with 30-second notice
   - Good for: CI/test jobs, non-critical builds

3. **Auto-scaling:** Reduce idle capacity during off-hours
   - Manual reduction: Set lower `max_capacity` during night hours
   - Scheduled scaling: Use Azure automation runbooks

4. **Right-sizing:** Choose appropriate SKU for workload
   - Don't overprovision: DS2_v2 often sufficient
   - Monitor actual CPU/memory usage

5. **Consolidation:** Run multiple smaller jobs on larger instances
   - Reduce instance count
   - Increase parallelism per instance

### Cost Monitoring

Enable Azure Cost Management alerts:

```bash
# Create budget alert
az billing budget create \
  --name "runner-budget" \
  --amount 5000 \
  --threshold-type Forecasted \
  --notifications-enabled true
```

---

## Monitoring and Adjustment

### Key Metrics to Monitor

1. **Queue Depth:** Pending jobs waiting for runners
2. **Instance Utilization:** CPU/memory per instance
3. **Scaling Events:** Frequency of scale-in/out
4. **Job Duration:** Execution time trends
5. **Cost Per Job:** Track cost efficiency

### Monitoring Dashboard

Use Azure Monitor to track:

```kusto
// Azure Monitor Query to check runner health
AzureMetrics
| where ResourceType == "Microsoft.Compute/virtualMachineScaleSets"
| where MetricName == "Percentage CPU"
| summarize AvgCPU = avg(Total) by bin(TimeGenerated, 5m)
| render timechart
```

### Adjustment Workflow

```
1. Monitor metrics for 2+ weeks
2. Identify capacity gaps (queue depth > 0 consistently)
3. Increase min_capacity or max_capacity
4. Test in staging environment first
5. Deploy to production with gradual rollout
6. Monitor for 1 week post-adjustment
7. Validate cost impact
```

### Scaling Triggers for Adjustment

| Metric | Current | Action |
|--------|---------|--------|
| Queue depth | > 5 consistently | Increase min_capacity |
| Peak CPU | > 85% | Increase min_capacity or max_capacity |
| Avg utilization | < 30% | Decrease min_capacity |
| Scaling events/hr | > 10 | Adjust cooldown or thresholds |

---

## Regional Considerations

### Region Selection

Choose region based on:
1. **Latency:** Closer to dev team and CI/CD infrastructure
2. **Cost:** Pricing varies by region (US regions typically cheapest)
3. **Availability:** Some regions have quota constraints
4. **Feature Support:** Newest Azure features in select regions

### Recommended Regions

- **US East:** eastus, eastus2 (good availability, lower cost)
- **US Central:** centralus (central location in US)
- **US West:** westus2, westus3 (West Coast preferred)

### Multi-Region Deployment

For high-availability:

```hcl
# Region 1: Primary
module "azure_scale_set_east" {
  source   = "../../modules/azure_scale_set"
  location = "eastus"
  capacity = 20
}

# Region 2: Secondary (failover)
module "azure_scale_set_west" {
  source   = "../../modules/azure_scale_set"
  location = "westus2"
  capacity = 10
}
```

---

## Quick Reference

### Capacity Planning Checklist

- [ ] Estimated concurrent jobs during peak
- [ ] Selected appropriate VM SKU
- [ ] Verified regional vCPU quotas (20% headroom)
- [ ] Configured min_capacity and max_capacity
- [ ] Set autoscaling thresholds
- [ ] Estimated monthly cost
- [ ] Set up monitoring and alerts
- [ ] Created runbook for capacity adjustments

### Example Terr form Configuration

```hcl
module "azure_runners_prod" {
  source = "../../modules/azure_scale_set"

  resource_group_name  = azurerm_resource_group.prod.name
  location             = "eastus"
  vm_sku               = "Standard_DS2_v2"
  
  # Capacity settings (plan for 20 concurrent jobs + 20% buffer)
  capacity       = 25
  min_capacity   = 10
  max_capacity   = 50
  enable_autoscaling = true
  
  # Runner configuration
  runner_labels = ["azure", "production", "linux"]
  runner_group  = "prod-azure-runners"
  environment   = "production"
  
  admin_username       = "azurerunner"
  admin_ssh_public_key = var.runner_ssh_key
  
  tags = {
    CostCenter = "Engineering"
    ManagedBy  = "Terraform"
  }
}
```

---

## Support and References

- [Azure VM Scale Sets Documentation](https://docs.microsoft.com/en-us/azure/virtual-machine-scale-sets/)
- [GitHub Actions Runner Documentation](https://docs.github.com/en/actions/hosting-your-own-runners)
- [Azure Pricing Calculator](https://azure.microsoft.com/en-us/pricing/calculator/)
- [Azure Cost Management](https://docs.microsoft.com/en-us/azure/cost-management-billing/)

For detailed questions, refer to GitHub Actions documentation or Azure support.
