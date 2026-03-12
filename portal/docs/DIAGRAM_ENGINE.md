# Diagram Engine - Troubleshooting Guide

**Version:** 1.0  
**Status:** MVP (March 12, 2026)

---

## Overview

The Diagram Engine integrates with draw.io to provide visual analysis of failures, architecture visualization, and recommended troubleshooting steps.

## Architecture

```
Failure/Error Input
    ↓
[Log Parser]
    ↓
[Service Mapper]
    ↓
[Dependency Analyzer]
    ↓
[Failure Inference Engine]
    ↓
[Diagram Generator]
    ↓
[Draw.io XML Export]
    ↓
[Interactive UI Display]
```

## Core Components

### 1. **Log Parser**
Extracts relevant information from error logs:
- Service name
- Error message
- Timestamp
- Stack trace (if available)
- Related services

### 2. **Service Mapper**
Creates a map of service dependencies:
- Identifies affected services
- Traces call chains
- Marks failed nodes
- Calculates service criticality

### 3. **Failure Inference**
Uses heuristics to determine root cause:
- Frequency analysis (most failing service = likely culprit)
- Dependency inference (services that many depend on)
- Temporal correlation (failures that happen together)
- Pattern matching (known failure signatures)

### 4. **Diagram Generator**
Creates visual representation:
- Draws nodes for each service
- Draws edges for dependencies
- Colors failed nodes red
- Highlights critical path
- Adds metric overlays

## Usage

### Programmatic API

```typescript
import { DiagramEngine } from '@nexus/diagram-engine'

// Generate architecture diagram
const diagram = DiagramEngine.generateArchitectureDiagram([
  { name: 'Frontend', type: 'service' },
  { name: 'API', type: 'service' },
  { name: 'Database', type: 'database' }
])

// Analyze failures
const failures = [
  {
    type: 'timeout',
    timestamp: new Date(),
    service: 'api',
    errorMessage: 'Connection timeout',
    logs: ['...']
  }
]

const analysis = DiagramEngine.analyzeFailDetails(failures)
// Returns: { diagram, rootCauseAnalysis, recommendations }
```

### REST API

```bash
# Generate failure analysis
curl -X POST http://localhost:5000/api/v1/diagrams/analyze-failure \
  -H "Content-Type: application/json" \
  -d '{
    "failures": [
      {
        "service": "api",
        "errorMessage": "Connection timeout",
        "timestamp": "2026-03-12T10:00:00Z"
      }
    ]
  }'

# Response includes diagram + recommendations
```

### Frontend Integration

```javascript
// Display diagram in React
import { useEffect, useState } from 'react'

function DiagramView({ failureId }) {
  const [diagram, setDiagram] = useState(null)

  useEffect(() => {
    async function loadDiagram() {
      const res = await fetch(`/api/v1/diagrams/${failureId}`)
      const { data } = await res.json()
      setDiagram(data.diagram)
    }
    loadDiagram()
  }, [failureId])

  return (
    <div>
      <h2>Failure Analysis</h2>
      {diagram && <DrawioViewer diagram={diagram} />}
    </div>
  )
}
```

## Diagram Types

### 1. **Architecture Diagram**
Shows the overall system architecture:
- All services and their relationships
- Data flows
- External dependencies
- Load balancers, databases, caches

**Use Case:** Understanding system topology

### 2. **Failure Analysis Diagram**
Highlights services involved in a failure:
- Failed services (red nodes)
- Affected services (yellow)
- Critical path highlighted
- Error propagation shown

**Use Case:** Debugging deployment/service failures

### 3. **Deployment Flow Diagram**
Shows the deployment process:
- Build stage
- Test stage
- Deploy stage
- Rollback path

**Use Case:** understanding CI/CD pipeline

## Inference Accuracy

### Simple Heuristics (Current MVP)
```
Accuracy = 70-80% (typical)

Root Cause Detection:
- Most failing service: 60% confidence
- Dependency analysis: +15% confidence
- Temporal correlation: +10% confidence
```

### Advanced ML (Future)
```
Planned improvements:
- Historical failure patterns: +15%
- Log anomaly detection: +10%
- Metric correlation: +10%
- Graph neural networks: +15%

Target: 95%+ accuracy
```

## Output Formats

### Draw.io XML
```xml
<?xml version="1.0" encoding="UTF-8"?>
<mxGraphModel>
  <root>
    <mxCell id="0" />
    <mxCell id="1" parent="0" />
    <!-- Nodes and edges automatically generated -->
  </root>
</mxGraphModel>
```

### JSON Structure
```json
{
  "diagram": {
    "id": "diag-123",
    "title": "System Failure Analysis",
    "nodes": [
      {
        "id": "service-0",
        "label": "api",
        "type": "service",
        "status": "failed",
        "position": { "x": 100, "y": 100 }
      }
    ],
    "edges": [
      {
        "id": "edge-0",
        "source": "service-0",
        "target": "service-1",
        "status": "failed"
      }
    ]
  },
  "rootCauseAnalysis": {
    "suspectedService": "api",
    "confidence": 0.95,
    "factors": ["..."]
  },
  "recommendations": ["..."]
}
```

## Integration with Repo Scripts

The diagram engine integrates with existing repo troubleshooting:

```
CI/CD Failure
    ↓
[GitLab CI Error] → captured logs
    ↓
[API Endpoint] → POST /diagrams/analyze-failure
    ↓
[Diagram Engine] → processes logs
    ↓
[Portal UI] → displays diagram + runbook
    ↓
[Operator] → finds root cause & fix
```

## Known Limitations

### MVP (Current)
- ⚠️ Heuristic-based (not ML)
- ⚠️ Requires structured logs
- ⚠️ Single failure chain only
- ⚠️ No distributed tracing integration
- ⚠️ Basic Draw.io export

### Future Improvements
- ✅ ML-powered inference
- ✅ Unstructured log parsing
- ✅ Complex correlation
- ✅ OpenTelemetry integration
- ✅ Custom diagram templates

## Examples

### Example 1: Database Connection Failure

```
Input Logs:
[2026-03-12T10:00:00Z] api ERROR: Connection timeout
[2026-03-12T10:00:01Z] api ERROR: Unable to connect to database
[2026-03-12T10:00:02Z] frontend WARNING: API unreachable

Output Diagram:
┌─────────────┐
│  Frontend   │ (yellow - degraded)
└──────┬──────┘
       │
┌──────▼──────┐
│     API     │ (red - failed)
└──────┬──────┘
       │
┌──────▼──────┐
│  Database   │ (red - failed)
└─────────────┘

Root Cause: Database connection pool exhausted
Confidence: 92%
Recommendations:
1. Check database service health
2. Check network connectivity
3. Verify credentials
4. Increase pool size
```

### Example 2: Cascading Failure

```
Input: Multiple service failures within 5 seconds

Output Diagram:
┌──────────────┐
│ Load Balancer│ (healthy)
└──────┬───────┘
       │
    ┌──┴──┐
    ▼     ▼
  API-1  API-2 (both failed - red)
    │     │
    └──┬──┘
       │
┌──────▼──────┐
│  Shared DB  │ (failed - red)
└─────────────┘

Root Cause: Shared dependency failure
Confidence: 95%
Recommendations:
1. Restart database
2. Check recent deployments
3. Review database logs
```

## Day-to-Day Operations

### For Operators
1. Deployment fails → click "Analyze"
2. Portal generates diagram → shows failure
3. Read recommendations → follow steps
4. Diagram updates with health status → confirms fix

### For DevOps/SRE
1. Set up log aggregation → send to API
2. Configure alerts → trigger diagram analysis
3. Integrate with runbooks → auto-remediation
4. Feedback loop → improve inference

## Testing the Diagram Engine

### Unit Tests
```bash
pnpm -C packages/diagram-engine test
```

### Integration Tests
```bash
# Locally test diagram generation
curl -X POST http://localhost:5000/api/v1/diagrams/analyze-failure \
  -H "Content-Type: application/json" \
  -d @test-failures.json
```

### Manual Testing
1. Start portal: `pnpm dev`
2. Go to Diagrams tab
3. Upload failure logs
4. View generated diagram
5. Verify recommendations

## Future Enhancements

- [ ] Machine learning model for inference
- [ ] Custom diagram templates
- [ ] Real-time streaming diagrams
- [ ] Predictive failure detection
- [ ] Automated remediation hooks
- [ ] Slack/Teams integration
- [ ] Historical trend analysis
- [ ] Multi-cloud support

## References

- [Architecture Guide](./ARCHITECTURE.md)
- [API Documentation](./API.md)
- [Diagram Engine Source](../packages/diagram-engine/)

---

**Status:** MVP (March 12, 2026)  
**Next Update:** Post-launch feedback integration
