# Architecture Decision Records (ADRs)

Architecture Decision Records document major design decisions in EIQ Nexus.

Each ADR captures:
- **What** decision was made
- **Why** it was necessary
- **Alternatives** considered
- **Consequences** (positive and negative)
- **Status** (Proposed, Accepted, Superseded, Deprecated)

---

## Active ADRs

| # | Title | Status | Date |
|---|-------|--------|------|
| 001 | [Autonomous Pipeline Repair System](ADR-0001-autonomous-pipeline-repair.md) | Proposed | 2024-03-05 |
| 002 | [Multi-Cloud Runner Architecture](ADR-0002-multi-cloud-runner-architecture.md) | Proposed | 2024-03-05 |
| 003 | [Distributed Intelligence Engine](ADR-0003-distributed-intelligence-engine.md) | Proposed | 2024-03-05 |
| 004 | [API-First Design Mandate](ADR-0004-api-first-mandate.md) | Proposed | 2024-03-05 |
| 005 | [Sovereign Control Plane Independence](ADR-0005-sovereign-independence.md) | Proposed | 2024-03-05 |

---

## Creating New ADRs

1. Use `ADR-NNNN-kebab-case-title.md` naming
2. Copy the [ADR Template](ADR-TEMPLATE.md)
3. Fill in all sections completely
4. Submit for review by @platform-architects
5. Update this index when approved

---

## Decision Process

1. **Proposal**: Create ADR in draft status
2. **Discussion**: Request feedback in GitHub
3. **Decision**: Platform architects approve/reject
4. **Implementation**: Code follows ADR
5. **Retrospective**: Assess outcomes after 6 months

---

## Links

- [ADR Template](ADR-TEMPLATE.md)
- [Contributing Guidelines](../../CONTRIBUTING.md)
- [Architecture](../../ARCHITECTURE.md)
- [Governance](../../GOVERNANCE.md)
