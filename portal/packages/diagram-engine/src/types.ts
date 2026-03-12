/**
 * Diagram types for troubleshooting and architecture
 */

export interface Position {
  x: number
  y: number
}

export interface DiagramNode {
  id: string
  label: string
  type: 'service' | 'database' | 'queue' | 'cache' | 'load-balancer' | 'error'
  position: Position
  metadata?: Record<string, unknown>
  status?: 'healthy' | 'degraded' | 'failed'
}

export interface DiagramEdge {
  id: string
  source: string
  target: string
  label?: string
  status?: 'healthy' | 'failed'
  metrics?: {
    latency?: number
    throughput?: number
    errorRate?: number
  }
}

export interface DiagramSchema {
  id: string
  title: string
  type: 'architecture' | 'failure-analysis' | 'deployment-flow'
  nodes: DiagramNode[]
  edges: DiagramEdge[]
  metadata: {
    createdAt: Date
    updatedAt: Date
    version: string
    description: string
  }
}

export interface FailureIndicator {
  type: string
  timestamp: Date
  service: string
  errorMessage: string
  stackTrace?: string
  logs: string[]
}

export interface TroubleshootingResult {
  diagramId: string
  diagram: DiagramSchema
  rootCauseAnalysis: {
    suspectedService: string
    confidence: number // 0-1
    factors: string[]
  }
  affectedPath: {
    nodes: string[]
    edges: string[]
  }
  recommendations: string[]
}
