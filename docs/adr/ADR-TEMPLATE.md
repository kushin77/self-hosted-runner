# ADR NNNN: [Title]

**Status**: Proposed | Accepted | Superseded | Deprecated  
**Date**: YYYY-MM-DD  
**Authors**: @author1, @author2  
**Supersedes**: ADR-XXXX (if applicable)  
**Superceded by**: ADR-XXXX (if applicable)  

---

## Context

What is the issue or problem we're facing that necessitates this decision?

Include relevant background:
- Current state of the system
- Pain points or limitations
- Context about why this matters now
- Stakeholders affected

---

## Problem Statement

Clear, specific statement of what we're trying to solve.

---

## Decision

What are we doing to solve this problem?

Describe the decision clearly and concisely.

---

## Rationale

Why did we choose this approach?

Include:
- Alignment with EIQ Nexus principles
- How it addresses the problem
- Why it's better than alternatives
- Long-term benefits

---

## Alternatives Considered

What other options did we evaluate?

For each alternative:
1. **Name**: Brief title
2. **Description**: How it would work
3. **Advantages**: Why it's good
4. **Disadvantages**: Why it's not chosen
5. **Why rejected**: Why we didn't pick this

### Alternative 1: [Name]

Description...

**Advantages:**
- ...

**Disadvantages:**
- ...

**Why rejected:** ...

### Alternative 2: [Name]

Description...

**Advantages:**
- ...

**Disadvantages:**
- ...

**Why rejected:** ...

---

## Consequences

### Positive Consequences

What good outcomes does this enable?

- ...
- ...
- ...

### Negative Consequences

What trade-offs or challenges does this create?

- ...
- ...
- ...

### Migration Path

If this changes existing behavior:
- How do existing systems migrate?
- What breaks?
- Timeline for migration
- Rollback strategy

---

## Enterprise Scale Validation

Does this work at EIQ Nexus enterprise scale?

- [ ] Millions of pipeline executions
- [ ] Thousands of concurrent runners
- [ ] Multi-region deployments
- [ ] Multi-cloud deployments
- [ ] Cost is acceptable at scale

**Analysis**: [Detailed validation]

---

## AI/Autonomous Impact

How does this affect AI-driven operations?

- Does it improve data accessibility for AI?
- Does it enable new autonomous capabilities?
- Does it change safety/approval requirements?
- Does it improve observability for ML models?

---

## Security Implications

Security considerations:

- Zero Trust compliance
- Secret isolation
- Audit requirements
- Authentication/Authorization implications
- Threat models addressed

---

## Observability Requirements

What observability signals does this provide?

- Logs: What gets logged?
- Metrics: What gets measured?
- Traces: What gets traced?
- Health checks: How is health determined?

---

## Testing Strategy

How will this be validated?

- Unit tests
- Integration tests
- Performance tests
- Security tests
- Chaos engineering validation
- Production validation approach

---

## Implementation Plan

Timeline and dependencies:

- **Phase 1**: [Description] - Timeline
- **Phase 2**: [Description] - Timeline
- **Phase 3**: [Description] - Timeline

### Rollout Strategy

- Canary deployment
- Feature flags
- Gradual rollout percentage
- Monitoring during rollout

---

## Rollback Plan

If adoption reveals problems, how do we roll back?

- Rollback triggers
- Rollback procedure
- Recovery timeline
- Data consistency handling

---

## Related Decisions

- Related to ADR-XXXX
- Depends on ADR-XXXX
- Supersedes ADR-XXXX
- Conflicts with: None

---

## References

- [Link to documentation]
- [Link to research]
- [Link to related discussion]
- [Link to RFC or proposal]

---

## Discussion

### Approval Checklist

- [ ] Platform architects reviewed
- [ ] Security team reviewed
- [ ] AI team reviewed (if applicable)
- [ ] Performance validated
- [ ] Scalability validated
- [ ] Observability planned

### Comments & Feedback

[Space for discussion comments]

---

## Implementation Notes

Once approved, add implementation notes here:

- **PR**: #XXX
- **Branch**: feature/xxx
- **Status**: In progress | Completed
- **Retrospective**: [Post-implementation assessment]

---

## Retrospective (6 months post-implementation)

After 6 months in production:

- **Did it solve the problem?**: Yes/No/Partially
- **Unexpected consequences?**: ...
- **Would we make the same decision?**: Yes/No
- **Lessons learned**: ...
- **Follow-up decisions needed?**: ...

---

**Last Updated**: YYYY-MM-DD  
**Next Review**: YYYY-MM-DD
