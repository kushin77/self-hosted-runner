# AI Agent Safety Framework for EIQ Nexus

This framework ensures AI agents operating EIQ Nexus do so safely, transparently, and within defined guardrails.

---

## Core Principles

### 1. Human-in-the-Loop for Critical Actions

Not all actions should be autonomous. Define approval gates based on risk.

### Risk Categories

**🟢 Green (Auto-Executable)**
- Log format changes
- Metric collection
- Cache invalidation
- Configuration reads
- Status checks

Auto-execute these actions without approval.

**🟡 Yellow (Requires Approval)**
- Increase timeouts (low cost impact)
- Enable optimizations (reversible)
- Scale up resources (within limits)
- Modify non-critical configurations
- Deploy canary changes

Require human approval before execution.

**🔴 Red (Forbidden)**
- Delete data
- Disable security controls
- Open firewall rules
- Reduce resource limits
- Force terminate workflows
- Modify authentication/authorization
- Disable audit logging

Never execute without explicit operational approval.

---

## Safety Guarantees

### 1. Autonomous Action Reversibility

**Every autonomous action must be reversible.**

**Example:**
```
Action: Increase timeout from 30s to 60s
Reversible? YES - Can reset to 30s
Safe to auto-execute: YES (with approval gate)

Action: Delete failed pipeline history
Reversible? NO - Data is lost
Safe to auto-execute: NO - Forbidden
```

### 2. Bounded Scope

**Autonomous actions must have clearly bounded scope.**

**Example:**
```
Good: Increase timeout for single pipeline
Bad: Increase timeout for all pipelines globally
```

**Example:**
```
Good: Scale runner pool +20% (up to 10 runners max)
Bad: Scale runner pool to unlimited
```

### 3. Safety Limits

**All autonomous actions must have absolute limits.**

```yaml
AutomatedOptimization:
  TimeoutIncrease:
    MaxIncrease: 2x original
    AbsoluteMax: 3600 seconds
    CostDelta: $10 per execution max

  RunnerScaling:
    MaxConcurrent: 50
    MaxCostPerHour: $500
    MaxRegionalDensity: 20% of capacity

  FeatureEnablement:
    RequiresBeta: false
    RequiresSecurityReview: false
    MaxChangesPerDay: 5
```

---

## Decision Trees

### Pipeline Repair

```
Failure Detected
  │
  ├─→ Safety Check
  │   ├─→ Is repair reversible? 
  │   │   └─→ NO → Require approval
  │   ├─→ Is repair bounded?
  │   │   └─→ NO → Require approval
  │   ├─→ Would repair create new risk?
  │   │   └─→ YES → Require approval
  │
  ├─→ Cost Check
  │   └─→ Cost delta > $50?
  │       └─→ YES → Require approval
  │
  └─→ Action
      ├─→ All checks pass → AUTO-REPAIR
      └─→ Any check fails → REQUEST APPROVAL
```

### Resource Provisioning

```
Scaling Request
  │
  ├─→ Capacity Check
  │   └─→ Available capacity < 20%?
  │       └─→ YES → Require approval
  │
  ├─→ Cost Check
  │   └─→ Monthly delta > $1000?
  │       └─→ YES → Require approval
  │
  ├─→ Performance Check
  │   └─→ Would improve latency > 10%?
  │       └─→ Auto-approve
  │   └─→ Would worsen availability?
  │       └─→ Require approval
  │
  └─→ Action
      ├─→ All checks pass → AUTO-SCALE
      └─→ Any check fails → REQUEST APPROVAL
```

---

## Approval Gates

### Required Approvals

| Action Type | Approval Required | Approver | Timeline |
|-------------|-------------------|----------|----------|
| Increase timeout | $50+ cost delta | ops-oncall | 30 mins |
| Scale resources | > 20% capacity | platform-ops | 30 mins |
| Enable feature | Breaking change | platform-architects | 4 hours |
| Disable service | Production impact | platform-architects | 4 hours |
| Modify security | Policy change | security-team | 24 hours |

### Approval Process

1. **Request Generated**
   ```json
   {
     "approval_request_id": "apr-789456",
     "action_type": "timeout_increase",
     "target": "pipeline-123",
     "change": "30s → 60s timeout",
     "cost_delta": "$0.15",
     "risk_level": "low",
     "approver_required": "ops-oncall",
     "urgency": "normal",
     "requested_at": "2024-03-05T14:30:00Z"
   }
   ```

2. **Approval Requested**
   - Notification sent to approver
   - Timeout set (depends on urgency)
   - Alternative actions suggested

3. **Approval Given/Denied**
   ```json
   {
     "approval_request_id": "apr-789456",
     "approved": true,
     "approver": "alice@elevatediq.com",
     "approval_time": "2024-03-05T14:35:00Z",
     "reason": "Standard timeout increase, within limits",
     "conditions": []
   }
   ```

4. **Action Executed**
   - Full audit trail recorded
   - Outcomes tracked
   - Rollback prepared

---

## Audit and Observability

### Complete Audit Trail

Every AI action is fully auditable:

```json
{
  "action_id": "act-789456",
  "action_type": "autonomous_repair",
  "ai_system": "pipeline_repair_v2.5",
  "timestamp": "2024-03-05T14:30:00Z",
  "target_type": "pipeline",
  "target_id": "pipe-123",
  "decision": {
    "reasoning": "Timeout exceeded 90% of executions, increasing by 20%",
    "confidence": 0.92,
    "alternatives_considered": 2,
    "decision_time_ms": 450
  },
  "change": {
    "type": "config_update",
    "field": "timeout_ms",
    "old_value": 30000,
    "new_value": 36000
  },
  "approval": {
    "required": false,
    "approval_request_id": null
  },
  "execution": {
    "status": "success",
    "execution_time_ms": 250,
    "errors": null
  },
  "outcome": {
    "pipeline_status": "succeeded",
    "duration_ms": 35000,
    "cost": "$0.18",
    "quality_improvement": "success"
  },
  "learning": {
    "prediction_accuracy": "correct",
    "feedback_recorded": true,
    "model_update": "pending_batch"
  }
}
```

### Key Metrics

Track AI system performance:

- **Autonomous Action Success Rate**: % of autonomous actions that succeed
- **Recommendation Acceptance Rate**: % of AI recommendations followed
- **Recommendation Accuracy**: % of recommendations that improve outcomes
- **False Positive Rate**: % of incorrect analyses
- **Approval Request Rate**: % of actions requiring approval
- **Appeal Rate**: % of approved actions that are reversed
- **Cost Impact**: $ saved/spent per AI action
- **Performance Impact**: Latency reduction per action

---

## Escalation Paths

### Decision Escalation

```
Low Risk Action
  ├─→ All checks pass
  └─→ AUTO-EXECUTE

Medium Risk Action
  ├─→ Check vs. guidelines
  ├─→ Within limits
  └─→ REQUEST APPROVAL (30 min timeout)
      ├─→ APPROVED → EXECUTE
      └─→ DENIED → LOG & NOTIFY

High Risk Action
  ├─→ Forbidden category
  └─→ ALWAYS REQUIRE MANUAL APPROVAL
      ├─→ APPROVED (with conditions) → EXECUTE with guardrails
      └─→ DENIED → DO NOT EXECUTE
```

### Escalation Pipeline

If action has concerning characteristics:

1. **Level 1**: ops-oncall (for urgent approvals)
2. **Level 2**: platform-ops (for capacity decisions)
3. **Level 3**: platform-architects (for design changes)
4. **Level 4**: security-team (for security changes)
5. **Level 5**: executive (for policy overrides)

---

## Testing and Validation

### Before Deploying AI Agent

1. **Safety Testing**
   - [ ] Reversibility validated
   - [ ] Boundaries tested
   - [ ] Edge cases handled
   - [ ] Error conditions tested

2. **Approval Gate Testing**
   - [ ] Approval requests generated correctly
   - [ ] Notifications sent
   - [ ] Timeouts work
   - [ ] Escalation paths function

3. **Audit Trail Testing**
   - [ ] All actions logged
   - [ ] All decisions recorded
   - [ ] Context captured
   - [ ] Searchable and queryable

4. **Impact Testing**
   - [ ] Cost calculations correct
   - [ ] Performance impact measured
   - [ ] Side effects identified
   - [ ] Rollback tested

### Canary Deployment

1. Start with 1% of actions
2. Monitor for errors
3. Increase to 10% if safe
4. Increase to 100% if stable
5. Maintain 50/50 approval split initially

---

## Policy and Enforcement

### Configuration

AI Safety Framework is configured via:

```yaml
AIAgentSafety:
  Version: 1.0
  Enabled: true
  
  ApprovalGates:
    EnabledForActions: ["timeout_increase", "resource_scale"]
    DisabledForActions: ["log_read", "metric_query"]
    
  AutomationLimits:
    TimeoutIncrease:
      MaxPercentage: 200%
      AbsoluteMax: 3600s
      DailyLimit: 10 actions
    ResourceScaling:
      MaxAdditive: 20%
      DailyLimitCost: "$1000"
      RegionalLimitPercent: 20%
      
  AuditRequirements:
    LogAllActions: true
    LogAllDecisions: true
    RetentionDays: 365
    
  SafetyChecks:
    EnforceReversibility: true
    RequireBoundedScope: true
    RequireRollback: true
```

---

## Continuous Improvement

### Monthly Review

1. **Audit Trail Analysis**
   - What actions are most common?
   - Which approval gates are most restrictive?
   - What's the approval rejection rate?

2. **Accuracy Metrics**
   - How accurate are AI recommendations?
   - What false positive rate?
   - What's being missed?

3. **User Feedback**
   - Is the framework helpful?
   - Are approval gates too restrictive?
   - Are safety limits appropriate?

4. **Policy Updates**
   - Should any green actions move to yellow?
   - Should any yellow actions move to green?
   - Are safety limits still appropriate?

---

## Escalation Procedures

### Incident Triggers

AI system must escalate if:

- 10+ consecutive action failures
- Any red-category action suggested
- Cost impact > $1000 in one hour
- Safety check failures
- Audit trail corruption

### Incident Response

1. **Immediate**: Disable autonomous actions
2. **Urgent**: Alert platform-architects
3. **Investigation**: Analyze what happened
4. **Recovery**: Manual review before resume
5. **Prevention**: Policy updates if needed

---

## Resources

- [AI Development Framework](../../AI_DEVELOPMENT.md)
- [Contributing Guidelines](../../CONTRIBUTING.md)
- [Architecture](../../ARCHITECTURE.md)
- [GOVERNANCE.md](../../GOVERNANCE.md)
