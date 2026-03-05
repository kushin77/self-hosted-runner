# Multi-Cloud Runner Architecture for EIQ Nexus

This document describes the architecture for operating runners across multiple cloud providers and on-premises infrastructure.

---

## Overview

EIQ Nexus manages distributed compute execution across:

- **AWS** (EC2, EKS, Lambda)
- **Google Cloud** (Compute Engine, GKE, Cloud Run)
- **Azure** (VMs, AKS, Container Instances)
- **On-Premises** (Kubernetes clusters, bare metal)
- **Edge** (Local runners, embedded infrastructure)

---

## Core Architecture

```
┌─────────────────────────────────────────────────────────┐
│  EIQ Nexus Control Plane                                │
│  • Runner orchestration engine                          │
│  • Cost optimization                                    │
│  • Global load balancing                                │
│  • ML-driven provisioning                               │
└────────────┬──────────┬──────────┬───────────┬──────────┘
             │          │          │           │
        ┌────▼──┐  ┌────▼──┐  ┌────▼──┐  ┌───▼────┐
        │  AWS  │  │  GCP  │  │Azure  │  │On-Prem │
        └─┬─────┘  └─┬─────┘  └─┬─────┘  └────────┘
          │         │         │
      ┌───┴────┐ ┌──┴────┐ ┌──┴────┐
      │ Region │ │Region │ │Region │
      │ 1      │ │ 2     │ │ 3     │
      └────────┘ └───────┘ └───────┘
```

---

## Layer Model

### Layer 1: Cloud Abstraction

Abstract cloud-specific details behind a unified interface.

```
┌────────────────────────────────────────┐
│  Nexus Runner Interface                │
│  • Create runner                       │
│  • Destroy runner                      │
│  • Monitor health                      │
│  • Report metrics                      │
└────────┬───────────────────┬───────────┘
         │                   │
    ┌────▼────┐         ┌────▼────┐
    │ AWS API │         │ GCP API │
    │ adapter │         │ adapter │
    └─────────┘         └─────────┘
```

### Layer 2: Regional Distribution

Each cloud region has independent runner pools.

```
┌──────────────────────────────────┐
│ AWS us-east-1 Region             │
├──────────────────────────────────┤
│ Runner Pool:                     │
│ • Min: 2 runners                 │
│ • Max: 50 runners                │
│ • Idle: 5 runners                │
│ • Current: 12 runners            │
└──────────────────────────────────┘
```

### Layer 3: Workload Distribution

Nexus decides where to route execution.

```
Pipeline Execution Request
  │
  ├─→ Analyze requirements (CPU, GPU, memory, location)
  │
  ├─→ Find compatible regions
  │   └─→ Filter by capability
  │   └─→ Filter by cost
  │   └─→ Filter by latency
  │
  ├─→ Calculate optimal location
  │   └─→ Minimize cost
  │   └─→ Minimize latency
  │   └─→ Balance load
  │
  └─→ Route to selected region
```

---

## Cloud Providers

### AWS Runners

**Instances:**
- EC2 (standard compute)
- EC2 Spot (cost-effective)
- EC2 Dedicated (guaranteed capacity)

**Orchestration:**
- Via EC2 API directly
- Via EKS (Kubernetes)

**Features:**
- Auto-scaling groups
- Regional distribution
- Spot fleet management
- Custom AMI support

**Cost Optimization:**
- Use Spot instances (80% savings)
- Right-size instances
- Terminate idle runners (> 5 min)
- Off-peak scaling

### GCP Runners

**Instances:**
- Compute Engine (standard)
- Preemptible VMs (cost-effective)
- Machine types (custom sizing)

**Orchestration:**
- Via GCP Compute API
- Via GKE (Kubernetes)

**Features:**
- Instance templates
- Regional distribution
- Preemptible instance pools
- Custom machine types

**Cost Optimization:**
- Use preemptible VMs (60-80% savings)
- Committed use discounts
- Right-size machine types
- Auto-scaling

### Azure Runners

**Instances:**
- Virtual Machines (standard)
- Spot VMs (cost-effective)
- Azure Container Instances

**Orchestration:**
- Via Azure Resource Manager
- Via AKS (Kubernetes)

**Features:**
- VM scale sets
- Regional distribution
- Spot VM pools
- Flexible sizing

**Cost Optimization:**
- Use Spot VMs (70-90% savings)
- Reserved instances
- Hybrid Benefit licensing
- Auto-scaling

### On-Premises Runners

**Infrastructure:**
- Kubernetes clusters
- Bare metal servers
- Docker hosts
- Virtual machines

**Orchestration:**
- Kubernetes API
- Docker API
- Custom provisioning

**Features:**
- Full control
- No cloud costs
- Data residency compliance
- Custom configurations

**Cost Model:**
- Capital expense for infrastructure
- Operational expense for management
- Electricity and cooling
- Network bandwidth

---

## Provisioning Strategy

### Predictive Scaling

EIQ Nexus predicts demand and provisions in advance.

```
Demand Forecasting:

Historical Data:
  ├─→ Pipeline execution history
  ├─→ Execution pattern by hour/day/week
  ├─→ seasonal trends

Model:
  └─→ ML model predicts next 24 hours

Provisioning:
  ├─→ Pre-allocate capacity
  ├─→ Minimize idle time
  └─→ Ensure availability
```

### Dynamic Backoff-Off

Scale down when demand drops.

```
Idle Runner Detection:

Monitor:
  ├─→ Runner availability
  ├─→ Time since last execution
  ├─→ Cost per runner per hour

Decision:
  ├─→ Runner idle > 10 minutes?
  │   └─→ Terminate runner
  ├─→ Runner idle > 5 minutes?
  │   └─→ Mark for termination
  └─→ Keep minimum pool running
```

### Cost-Optimized Routing

Route work to cheapest available capacity.

```
Routing Decision:

For each compatible region:
  Calculate: Cost per execution + Latency cost + Availability risk

Route to: Option with lowest total cost

Example:
  AWS (us-east-1):   $0.08 + $0.005 latency cost
  GCP (us-central1): $0.06 + $0.001 latency cost ← CHOOSE
  Azure (eastus):    $0.07 + $0.002 latency cost
```

---

## Health and Resilience

### Runner Health Checks

Every runner reports health periodically.

```
Health Report:
{
  "runner_id": "runner-789456",
  "cloud": "aws",
  "region": "us-east-1",
  "timestamp": "2024-03-05T14:30:25Z",
  "status": "healthy",
  "metrics": {
    "cpu_usage": 0.45,
    "memory_usage": 0.60,
    "disk_usage": 0.75,
    "uptime_hours": 48.5
  },
  "capacity": {
    "concurrent_executions": 4,
    "available_slots": 2
  }
}
```

### Unhealthy Runner Recovery

```
Health Check Failure
  │
  ├─→ Single failure: LOG, continue monitoring
  │
  ├─→ 3 consecutive failures within 5 min
  │   └─→ Mark DEGRADED
  │   └─→ Stop routing new work
  │   └─→ Attempt recovery (reboot)
  │
  ├─→ 5 consecutive failures within 10 min
  │   └─→ Mark DEAD
  │   └─→ Terminate runner
  │   └─→ Provision replacement
  │
  └─→ Recovery succeeded
      └─→ Mark HEALTHY
      └─→ Resume accepting work
```

### Regional Failover

If a region experiences issues:

```
Region Health Monitoring:

AWS us-east-1:
  ├─→ Health check API endpoint
  ├─→ Monitor runner populations
  ├─→ Track error rates

If us-east-1 becomes unhealthy:
  ├─→ Stop routing NEW work to us-east-1
  ├─→ Complete EXISTING work
  ├─→ Route to us-west-2 instead
  └─→ Alert operations team
```

---

## Cost Management

### Cost Tracking

All execution costs attributed to:

- **Team**: Which team ran the pipeline?
- **Project**: Which project/application?
- **Pipeline**: Which pipeline?
- **Stage**: Which pipeline stage?
- **Resource**: CPU, memory, GPU, data transfer

```json
{
  "execution_id": "exec-789456",
  "team": "platform",
  "project": "infra",
  "pipeline": "deploy",
  "stage": "build",
  "cloud": "aws",
  "region": "us-east-1",
  "instance_type": "c5.xlarge",
  "duration_seconds": 1200,
  "cost": {
    "compute": "$0.45",
    "data_transfer": "$0.02",
    "storage": "$0.01",
    "total": "$0.48"
  }
}
```

### Cost Optimization Recommendations

EIQ Nexus continuously recommends optimizations:

- **Right-sizing**: Use smaller instance types
- **Spot savings**: Increase Spot instance usage
- **Regional arbitrage**: Route to cheaper regions
- **Off-peak scheduling**: Shift work to off-peak hours
- **Pipeline optimization**: Reduce runtime

**Example Recommendation:**
```
Opportunity: Instance Right-Sizing

Pipeline: "unit-tests"
Current: c5.2xlarge (8 vCPU, 16 GB)
Actual Peak Usage: 2 vCPU, 4 GB
Recommended: t3.large (2 vCPU, 8 GB)

Current Cost: $0.34/hour
Recommended Cost: $0.08/hour
Monthly Savings: ~$190
```

---

## Kubernetes Integration

### Preferred Deployment Model

Use Kubernetes across all cloud providers:

```
┌──────────────────────┐
│ Multi-Cloud K8s      │
├──────────────────────┤
│ • EKS (AWS)          │
│ • GKE (GCP)          │
│ • AKS (Azure)        │
│ • Self-managed (on-prem)
└──────────────────────┘
        │
   Unified API
        │
  Nexus Control Plane
```

### Benefits

- **Unified API**: Same API across all clouds
- **Portability**: Move workloads between clouds
- **Cost optimization**: Easy load balancing
- **Scalability**: Native horizontal scaling
- **Observability**: Standard observability patterns

### Runner as Kubernetes Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nexus-runner
  namespace: nexus-runners
  labels:
    app: nexus-runner
    cloud: aws
    region: us-east-1
spec:
  replicas: 5
  selector:
    matchLabels:
      app: nexus-runner
  template:
    metadata:
      labels:
        app: nexus-runner
    spec:
      containers:
      - name: runner
        image: nexus/runner:latest
        env:
        - name: RUNNER_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: CLOUD
          value: "aws"
        - name: REGION
          value: "us-east-1"
        resources:
          requests:
            cpu: 2
            memory: 4Gi
          limits:
            cpu: 4
            memory: 8Gi
```

---

## GPU Support

### GPU Workload Types

EIQ Nexus supports GPU-accelerated workloads:

- **AI/ML training**: TensorFlow, PyTorch
- **Data processing**: RAPIDS, Dask
- **Media encoding**: FFmpeg, Handbrake
- **Rendering**: Blender, RayTracing

### GPU Instance Selection

```
GPU Request:
  ├─→ GPU type (NVIDIA T4, A100, etc.)
  ├─→ GPU count (1-8)
  └─→ Memory requirements

Find compatible instances:
  ├─→ AWS (p3.2xlarge with Tesla V100)
  ├─→ GCP (Tesla P100)
  ├─→ Azure (Tesla V100)

Select cheapest:
  └─→ GCP with Preemptible instances
      Cost: $0.35/hour (vs $3/hour on AWS)
```

### Cost Efficiency

- Use Spot/Preemptible instances (80% savings)
- Batch small GPU jobs onto shared instances
- Terminate unused GPU runners immediately
- Use cheaper GPU types when possible

---

## Security and Isolation

### Per-Tenant Isolation

Each organization gets isolated runner pools:

```
AWS Account A (Team A):
  ├─→ Runners in private VPC
  ├─→ Separate IAM role
  ├─→ Encrypted storage
  └─→ Network isolation from Team B

AWS Account B (Team B):
  ├─→ Runners in private VPC
  ├─→ Separate IAM role
  ├─→ Encrypted storage
  └─→ Network isolation from Team A
```

### BYOC (Bring Your Own Cloud)

Organizations can bring their own cloud accounts:

```
Setup:

1. Customer provides AWS account
2. Nexus deploys runners to their account
3. Runners connect to Nexus control plane
4. Runners are dedicated to customer
5. Customer maintains their own cloud costs

Benefits:
  ├─→ Data never leaves customer's cloud
  ├─→ Compliance requirements met
  ├─→ Cost visibility and control
  └─→ Zero trust architecture
```

---

## Monitoring and Observability

### Metrics

All runners emit metrics:

- **CPU usage**: Percent utilization
- **Memory usage**: Bytes used / total
- **Network I/O**: Bytes in/out
- **Execution latency**: Time to complete
- **Cost per execution**: Real-time tracking
- **Error rates**: Failures per region

### Dashboards

Via Grafana or similar:

```
Multi-Cloud Runner Dashboard:
  ├─→ Runner count by cloud/region
  ├─→ Cost breakdown
  ├─→ Health status
  ├─→ Execution latency (by region)
  ├─→ Utilization trends
  └─→ Cost optimization opportunities
```

---

## Disaster Recovery

### Region Failover

If a region becomes unavailable:

```
Trigger: Region health check fails

Action:
  1. Stop routing NEW work to affected region
  2. Complete EXISTING work (if safe)
  3. Terminate unhealthy runners
  4. Route to healthy regions
  5. Alert operations team
  6. Investigate root cause

Timeline:
  ├─→ Detection: < 2 minutes
  ├─→ Failover: < 5 minutes
  ├─→ Full recovery: < 15 minutes
  └─→ Manual intervention: > 30 minutes
```

### Data Resilience

- All state stored in control plane (not regional)
- Execution logs replicated globally
- Cost data backed up
- Configuration versioned and auditable

---

## Configuration Example

```yaml
Runners:
  DefaultCloud: aws
  DefaultRegion: us-east-1
  
  Pools:
    - Name: "standard"
      InstanceType: "t3.large"
      MinReplicas: 2
      MaxReplicas: 50
      IdleTimeout: 300s
      RequiredGPU: null
      
    - Name: "gpu-intensive"
      InstanceType: "g4dn.xlarge"
      MinReplicas: 1
      MaxReplicas: 20
      IdleTimeout: 600s
      RequiredGPU: "T4"
      
  CloudConfigs:
    AWS:
      Regions:
        - us-east-1
        - us-west-2
        - eu-west-1
      EKSCluster: "nexus-primary"
      
    GCP:
      Regions:
        - us-central1
        - europe-west1
      GKECluster: "nexus-gke"
      PreemptiblePercent: 70
      
    Azure:
      Regions:
        - eastus
        - westeurope
      AKSCluster: "nexus-aks"
      SpotPercent: 60
      
  CostManagement:
    MaxCostPerExecution: "$50"
    DailyBudgetLimit: "$5000"
    PreferredProviders:
      - "spot/preemptible"
      - "on-premises"
      - "committed-reserves"
```

---

## Related Documentation

- [Architecture](../../ARCHITECTURE.md)
- [AI Development](../../AI_DEVELOPMENT.md)
- [Contributing](../../CONTRIBUTING.md)
