import { v4 as uuidv4 } from 'uuid'
import type { DiagramSchema, DiagramNode, DiagramEdge, FailureIndicator, TroubleshootingResult } from './types'

/**
 * Core diagram generation engine
 */
export class DiagramEngine {
  /**
   * Generate architecture diagram from service list
   */
  static generateArchitectureDiagram(services: Array<{ name: string; type: string }>): DiagramSchema {
    const nodes: DiagramNode[] = services.map((service, index) => ({
      id: `service-${index}`,
      label: service.name,
      type: (service.type as any) || 'service',
      position: {
        x: index * 200,
        y: 100
      },
      status: 'healthy'
    }))

    // Add edges between services (simple linear for now)
    const edges: DiagramEdge[] = []
    for (let i = 0; i < nodes.length - 1; i++) {
      edges.push({
        id: `edge-${i}`,
        source: nodes[i].id,
        target: nodes[i + 1].id,
        status: 'healthy'
      })
    }

    return {
      id: uuidv4(),
      title: 'System Architecture',
      type: 'architecture',
      nodes,
      edges,
      metadata: {
        createdAt: new Date(),
        updatedAt: new Date(),
        version: '1.0.0',
        description: 'Auto-generated architecture diagram'
      }
    }
  }

  /**
   * Generate failure analysis diagram from error logs
   */
  static generateFailureAnalysisDiagram(failures: FailureIndicator[]): DiagramSchema {
    const affectedServices = new Set(failures.map(f => f.service))
    
    const nodes: DiagramNode[] = Array.from(affectedServices).map((service, index) => ({
      id: `service-${index}`,
      label: service,
      type: 'error',
      position: {
        x: index * 200,
        y: 100
      },
      status: 'failed'
    }))

    // Create edges between affected services
    const edges: DiagramEdge[] = []
    for (let i = 0; i < nodes.length - 1; i++) {
      edges.push({
        id: `edge-${i}`,
        source: nodes[i].id,
        target: nodes[i + 1].id,
        status: 'failed',
        metrics: {
          errorRate: 100
        }
      })
    }

    return {
      id: uuidv4(),
      title: 'Failure Analysis',
      type: 'failure-analysis',
      nodes,
      edges,
      metadata: {
        createdAt: new Date(),
        updatedAt: new Date(),
        version: '1.0.0',
        description: `Failure analysis diagram with ${failures.length} errors`
      }
    }
  }

  /**
   * Analyze failures and generate troubleshooting results
   */
  static analyzeFail Details(failures: FailureIndicator[]): TroubleshootingResult {
    const diagram = this.generateFailureAnalysisDiagram(failures)
    
    // Simple heuristic: most frequently failing service is likely root cause
    const failureMap = new Map<string, number>()
    failures.forEach(f => {
      failureMap.set(f.service, (failureMap.get(f.service) || 0) + 1)
    })

    const sortedServices = Array.from(failureMap.entries()).sort((a, b) => b[1] - a[1])
    const suspectedService = sortedServices[0]?.[0] || 'unknown'

    return {
      diagramId: diagram.id,
      diagram,
      rootCauseAnalysis: {
        suspectedService,
        confidence: Math.min(0.95, sortedServices[0]?.[1] || 0 / failures.length),
        factors: [
          `Service "${suspectedService}" appears in ${sortedServices[0]?.[1] || 0} failures`,
          'Check service logs for detailed error information',
          'Verify service dependencies are healthy'
        ]
      },
      affectedPath: {
        nodes: diagram.nodes.map(n => n.id),
        edges: diagram.edges.map(e => e.id)
      },
      recommendations: [
        `1. Check logs for service "${suspectedService}"`,
        '2. Verify database connectivity',
        '3. Check external API dependencies',
        '4. Review recent deployments',
        '5. Consult runbooks for recovery procedures'
      ]
    }
  }

  /**
   * Convert diagram to Draw.io XML format
   */
  static toDraw(_object: DiagramSchema): string {
    // This is a placeholder for actual Draw.io XML conversion
    // Real implementation would generate proper Draw.io XML
    return `<?xml version="1.0" encoding="UTF-8"?>
<mxGraphModel>
  <root>
    <mxCell id="0" />
    <mxCell id="1" parent="0" />
    <!-- Generated diagram: ${_object.title} -->
  </root>
</mxGraphModel>`
  }
}
