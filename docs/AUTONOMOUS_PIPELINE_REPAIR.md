# Autonomous Pipeline Repair Engine for EIQ Nexus

This document describes how EIQ Nexus automatically detects and repairs failed pipelines.

---

## Purpose

Autonomous pipeline repair reduces manual debugging and accelerates software delivery.

Goals:
- **Reduce MTTR** (mean time to repair)
- **Reduce engineering toil** (manual debugging)
- **Improve reliability** (faster detection)
- **Increase productivity** (engineers focus on features)

---

## Architecture

```
Pipeline Failure
  │
  ├─→ Failure Detection
  │   └─→ Collect execution logs
  │   └─→ Identify error signals
  │   └─→ Classify failure type
  │
  ├─→ Root Cause Analysis
  │   └─→ Analyze logs and metrics
  │   └─→ Correlate with infrastructure
  │   └─→ Identify root cause (ML model)
  │
  ├─→ Repair Generation
  │   └─→ Match against known fixes
  │   └─→ Generate recommendations
  │   └─→ Validate fix safety
  │
  ├─→ Approval / Execution
  │   ├─→ Low-risk repairs: auto-execute
  │   ├─→ Medium-risk repairs: request approval
  │   └─→ High-risk repairs: human decision only
  │
  └─→ Outcome Tracking
      └─→ Monitor repair effectiveness
      └─→ Update models
      └─→ Improve recommendations
```

---

## Failure Classification

### Timeout Failures

**Detection:**
```
Error Signal: "Execution timeout after 30 seconds"
Confidence: High
Pattern: Occurs in same step consistently
Trend: Increasing over past 10 executions
```

**Root Causes:**
- External API slowdown
- Insufficient compute resources
- Network issues
- Step efficiency regression

**Repairs:**
1. **Increase timeout** (low risk)
2. **Optimize step logic** (medium risk)
3. **Provision more resources** (high risk)
4. **Split into parallel steps** (medium risk)

### Out-of-Memory Failures

**Detection:**
```
Error Signal: "Process killed: Out of memory"
Confidence: High
Pattern: Occurs on large inputs
Trend: 60% failure rate in step
```

**Root Causes:**
- Memory leak in step
- Unexpected large input
- Insufficient memory allocation
- Configuration regression

**Repairs:**
1. **Increase memory allocation** (low risk)
2. **Process in batches** (medium risk)
3. **Update dependencies** (medium risk)
4. **Optimize data structures** (high risk)

### Network Failures

**Detection:**
```
Error Signal: "Connection timeout to api.example.com"
Confidence: High
Pattern: Fails connecting to external service
Trend: 100% of requests failing
```

**Root Causes:**
- External service down
- Network connectivity issue
- DNS resolution failure
- Firewall/security group blocking

**Repairs:**
1. **Enable retries with backoff** (low risk)
2. **Route through proxy/VPN** (medium risk)
3. **Fallback to cached data** (medium risk)
4. **Disable external service** (high risk)

### Dependency Failures

**Detection:**
```
Error Signal: "Cannot resolve package: foo@^2.0.0"
Confidence: High
Pattern: Dependency-related error
Trend: New in past 24 hours
```

**Root Causes:**
- Package removed from registry
- Dependency version conflict
- Registry downtime
- Network access issue

**Repairs:**
1. **Lock to working version** (medium risk)
2. **Update lock file** (low risk)
3. **Clear cache and retry** (low risk)
4. **Update all dependencies** (high risk)

### Infrastructure Failures

**Detection:**
```
Error Signal: "Disk full: /mnt/data"
Confidence: High
Pattern: Step fails consistently
Trend: First occurrence
```

**Root Causes:**
- Insufficient disk space
- Cached artifacts growing
- Log rotation disabled
- Previous cleanup failed

**Repairs:**
1. **Clean artifact cache** (low risk)
2. **Increase runner disk size** (low risk)
3. **Enable log rotation** (low risk)
4. **Implement cleanup routine** (medium risk)

---

## Repair Strategies

### Strategy 1: Retry with Exponential Backoff

**When to use:**
- Transient failures (network timeouts, brief service unavailability)
- Idempotent operations

**Example:**
```
Failure: Connection timeout to external API
Repair: Retry with exponential backoff
  ├─→ Attempt 1: Wait 1 second, retry
  ├─→ Attempt 2: Wait 2 seconds, retry
  ├─→ Attempt 3: Wait 4 seconds, retry
  ├─→ Attempt 4: Wait 8 seconds, retry
  └─→ Attempt 5: Fail
```

**Execution:**
- Fully automated
- No approval needed
- Safe to execute immediately

### Strategy 2: Configuration Adjustment

**When to use:**
- Insufficient resource allocation
- Missing or incorrect settings

**Example:**
```
Failure: Execution timeout after 30 seconds
Repair: Increase timeout to 60 seconds
  ├─→ Modify pipeline configuration
  ├─→ Cost impact: < $1
  ├─→ Risk: Low
  └─→ Expected success rate: 85%
```

**Execution:**
- Low-cost changes: Auto-execute
- High-cost changes: Request approval
- Always create rollback

### Strategy 3: Resource Provisioning

**When to use:**
- Insufficient compute capacity
- Out of memory / disk failures

**Example:**
```
Failure: Out of memory in build step
Repair: Scale runner from t3.large to t3.xlarge
  ├─→ Memory increase: 8 GB → 16 GB
  ├─→ Cost increase: $0.08 → $0.13 per hour
  ├─→ Risk: Medium
  └─→ Expected success rate: 90%
```

**Execution:**
- Cost delta < $50: Auto-execute
- Cost delta > $50: Request approval
- Scale down after fix if not needed

### Strategy 4: Dependency Update

**When to use:**
- Dependency failures
- Compatibility issues
- Security vulnerabilities

**Example:**
```
Failure: Cannot resolve package foo@^2.0.0
Repair Options:
  a) Update lock file with compatible version
  b) Pin to last working version
  c) Try alternate package
```

**Execution:**
- Requires code change (PR)
- Not auto-executed
- Requires human review and approval

### Strategy 5: Workflow Optimization

**When to use:**
- Efficiency improvements
- Architectural changes

**Example:**
```
Failure: Pipeline takes 45 minutes (timeout is 30 min)
Repair: Parallelize build steps
  ├─→ Serial execution: 45 minutes
  ├─→ Parallel execution: 20 minutes
  ├─→ Code change: Medium
  ├─→ Risk: Medium
  └─→ Expected success rate: 80%
```

**Execution:**
- Requires code review
- Not auto-executed
- Optimal approach but needs approval

---

## Repair Safety

### Risk Assessment

Each repair is evaluated for risk:

```
Risk Factors:

1. Reversibility
   ├─→ Can we undo this? (reversible = lower risk)
   └─→ Increasing timeout? YES (reversible)
   
2. Scope
   ├─→ Does this affect other pipelines?
   └─→ Single pipeline change? (isolated = lower risk)
   
3. Cost
   ├─→ What's the financial impact?
   └─→ < $10 monthly impact? (low cost = lower risk)
   
4. Success Rate
   ├─→ How confident are we?
   └─→ > 85% confident? (high confidence = lower risk)
   
5. Execution Speed
   ├─→ How fast can we execute?
   └─→ < 5 minutes? (fast = lower risk)

Combined Risk Score:
  Low Risk   = Auto-execute
  Medium Risk = Request approval
  High Risk  = Human decides
```

### Approval Gates

```
Auto-Execute (Low Risk):
  ├─→ Timeout increase (< 2x, < $10 cost)
  ├─→ Retry with backoff
  ├─→ Cache clear
  ├─→ Runner restart
  └─→ Log rotation enable

Request Approval (Medium Risk):
  ├─→ Resource scaling ($10-$100 cost)
  ├─→ Dependency version lock
  ├─→ Configuration changes (moderate impact)
  └─→ Retry strategy enable

Require Human Decision (High Risk):
  ├─→ Major pipeline restructure
  ├─→ External service disable
  ├─→ Data deletion
  ├─→ Security setting change
  └─→ > $100 cost impact
```

---

## Machine Learning Integration

### Failure Prediction Model

ML model predicts failures 24 hours before they occur:

```
Features:
  ├─→ Historical execution times (trend)
  ├─→ Resource usage patterns
  ├─→ External API response times
  ├─→ Code changes in last commit
  ├─→ Dependency updates
  └─→ Infrastructure changes

Training Data:
  └─→ 90 days of execution history

Model Output:
  ├─→ Probability of failure (0-100%)
  ├─→ Predicted failure type
  ├─→ Recommended repair
  └─→ Time until failure (hours)

Example:
  Probability: 87% failure within 24 hours
  Reason: Timeout rate increased 40%
  Repair: Increase timeout + optimize
  Confidence: 0.92
```

### Repair Recommendation Model

ML model recommends the best repair strategy:

```
Input:
  ├─→ Failure type and error signals
  ├─→ Historical execution metrics
  ├─→ Similar failures from other pipelines
  └─→ Success rates of various repairs

Output:
  ├─→ Repair option 1 (success rate: 92%)
  ├─→ Repair option 2 (success rate: 78%)
  └─→ Repair option 3 (success rate: 45%)

Example:
  Failure: Timeout in docker build step
  
  Option A: Increase timeout (92% success)
    └─→ Cost: +$0.05/execution
  
  Option B: Enable layer caching (78% success)
    └─→ Cost: +$0.02/execution
    └─→ Implementation: Code change
  
  Option C: Parallel stages (45% success)
    └─→ Cost: -$0.10/execution
    └─→ Implementation: Architecture change
  
  Recommend: Option A (highest success rate, auto-executable)
```

---

## Implementation

### Detection Service

```go
type FailureDetector struct {
  // Watch for failures
  
  func (f *FailureDetector) Monitor(ctx context.Context, execution *Execution) {
    // Monitor execution
    
    if execution.Failed() {
      failure := classifyFailure(execution)
      rootCause := analyzeRootCause(failure)
      recommend := recommendRepair(rootCause)
      
      executeOrApprove(recommend)
    }
  }
}
```

### Analysis Service

```go
type RootCauseAnalyzer struct {
  // Analyze failure root causes
  
  func (r *RootCauseAnalyzer) Analyze(failure *Failure) *RootCause {
    // Collect signals
    signals := collectSignals(failure)
    
    // Correlate with infrastructure
    correlation := correlateWithMetrics(signals)
    
    // Run ML model
    prediction := mlModel.Predict(correlation)
    
    return prediction.RootCause()
  }
}
```

### Repair Engine

```go
type RepairEngine struct {
  // Generate and execute repairs
  
  func (r *RepairEngine) Repair(rootCause *RootCause) *RepairResult {
    // Generate repair options
    options := generateRepairOptions(rootCause)
    
    // Assess risk
    for _, option := range options {
      option.Risk = assessRisk(option)
    }
    
    // Select best option
    best := selectBestOption(options)
    
    // Execute or approve
    if best.Risk == LowRisk {
      return r.ExecuteRepair(best)
    } else {
      return r.RequestApproval(best)
    }
  }
}
```

### API

```
POST /api/v1/repairs/pipeline/{pipeline_id}/auto

GET /api/v1/repairs/{repair_id}
GET /api/v1/repairs/{repair_id}/status
POST /api/v1/repairs/{repair_id}/approve
POST /api/v1/repairs/{repair_id}/deny
POST /api/v1/repairs/{repair_id}/rollback

GET /api/v1/analytics/repair-effectiveness
GET /api/v1/analytics/failure-predictions
```

---

## Observability

### Metrics

Track repair system performance:

```
repair_detection_latency_seconds
  └─→ Time from failure to detection
  └─→ Target: < 10 seconds

repair_execution_latency_seconds
  └─→ Time from detection to repair execution
  └─→ Target: < 30 seconds

repair_success_rate
  └─→ % of repairs that succeed
  └─→ Target: > 85%

repair_approval_rate
  └─→ % of repairs approved by humans
  └─→ Target: < 30%

repair_rollback_rate
  └─→ % of repairs that get rolled back
  └─→ Target: < 5%

mttr_reduction
  └─→ Reduction in mean time to repair
  └─→ Target: > 50%
```

### Dashboards

Via Grafana:

```
Autonomous Repair Dashboard:
  ├─→ Repairs executed (last 24h)
  ├─→ Success rate by repair type
  ├─→ MTTR before/after repair
  ├─→ Cost impact of repairs
  ├─→ Approval request volume
  └─→ Top failure types
```

### Logging

All repairs logged for audit:

```json
{
  "repair_id": "rep-789456",
  "timestamp": "2024-03-05T14:30:00Z",
  "pipeline_id": "pipe-123",
  "failure_type": "timeout",
  "root_cause": "docker_layer_cache_miss",
  "repair_type": "increase_timeout",
  "repair_config": {
    "old_timeout": 30000,
    "new_timeout": 60000
  },
  "risk_assessment": {
    "reversibility": "high",
    "scope": "isolated",
    "cost_delta": 0.15,
    "success_confidence": 0.92,
    "overall_risk": "low"
  },
  "approval": {
    "required": false,
    "auto_approved": true
  },
  "execution": {
    "status": "success",
    "duration_ms": 250,
    "outcome": "pipeline_succeeded"
  }
}
```

---

## Configuration

```yaml
AutonomousRepair:
  Enabled: true
  
  Strategies:
    TimeoutIncrease:
      Enabled: true
      MaxIncrease: 300% # 3x original
      MaxAbsolute: 3600 # 1 hour
      CostDeltaLimit: $10
      AutoExecute: true
      
    ResourceScaling:
      Enabled: true
      MaxCPUIncrease: 200%
      MaxMemoryIncrease: 200%
      CostDeltaLimit: $50
      AutoExecute: false # requires approval
      
    DependencyUpdate:
      Enabled: true
      MaxVersionJump: minor # major, minor, patch
      SecurityUpdates: auto
      RequiresCodeReview: true
      
    RetryWithBackoff:
      Enabled: true
      MaxAttempts: 5
      InitialDelayMs: 1000
      MaxDelayMs: 30000
      AutoExecute: true
  
  SafetyGates:
    RequireReversibility: true
    RequireBoundedScope: true
    RequireRollback: true
    
  ApprovalThresholds:
    CostDeltaLimit: $50
    ExecutionCostLimit: $1000
    DailyBudgetLimit: $5000
    
  Monitoring:
    SuccessRateTarget: 0.85
    ApprovalRateTarget: 0.30
    RollbackRateTarget: 0.05
```

---

## Results and Metrics

### MTTR Improvement

**Before Autonomous Repair:**
- Average MTTR: 45 minutes
- Engineering time: 1-2 hours per incident

**After Autonomous Repair:**
- Average MTTR: 5-10 minutes
- Engineering time: 10 minutes per incident

**Impact:** 75-90% reduction in MTTR

### Cost Impact

**Infrastructure Improvements:**
- Increased utilization: +15%
- Faster recovery: -20% duplicate work
- Optimized resources: -10% cost

**Engineering Productivity:**
- Reduced debugging time: +300%
- Faster deployments: +50%
- Fewer manual failures: -60%

---

## Related Documentation

- [AI Development](architecture/AI_DEVELOPMENT.md)
- [AI Agent Safety](AI_AGENT_SAFETY_FRAMEWORK.md)
- [Architecture](../../ARCHITECTURE.md)
- [Contributing](../ElevatedIQ-Mono-Repo/apps/portal/node_modules/recharts/CONTRIBUTING.md)
