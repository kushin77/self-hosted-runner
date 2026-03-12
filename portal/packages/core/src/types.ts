/**
 * Core shared types for NexusShield Portal
 */

export interface IProduct {
  id: string
  name: string
  description: string
  status: 'active' | 'beta' | 'future'
  version: string
  icon: string
  features: string[]
  apiUrl: string
  permissions: string[]
}

export interface IUser {
  id: string
  email: string
  name: string
  role: 'admin' | 'operator' | 'viewer'
  permissions: string[]
  createdAt: Date
  lastLogin: Date
}

export interface IDeployment {
  id: string
  name: string
  environment: 'development' | 'staging' | 'production'
  status: 'pending' | 'running' | 'success' | 'failed'
  version: string
  startTime: Date
  endTime?: Date
  duration?: number
  logs: string
  deployedBy: string
  metadata: Record<string, unknown>
}

export interface ISecret {
  id: string
  name: string
  type: 'database' | 'api-key' | 'certificate' | 'token'
  status: 'active' | 'rotating' | 'expired'
  rotationPolicy: {
    enabled: boolean
    interval: number
    lastRotated: Date
  }
  expiresAt: Date
  createdAt: Date
}

export interface IAlert {
  id: string
  title: string
  severity: 'critical' | 'high' | 'medium' | 'low'
  status: 'triggered' | 'acknowledged' | 'resolved'
  timestamp: Date
  source: string
  metadata: Record<string, unknown>
}

export interface IDiagram {
  id: string
  title: string
  type: 'architecture' | 'troubleshooting' | 'workflow'
  xml: string
  generatedAt: Date
  relatedTo?: {
    type: 'deployment' | 'failure' | 'alert'
    id: string
  }
}

export interface IFailureAnalysis {
  id: string
  failureType: string
  rootCause?: string
  affectedServices: string[]
  timeline: Array<{
    timestamp: Date
    event: string
    details: Record<string, unknown>
  }>
  diagram?: IDiagram
  recommendations: string[]
}

export interface IServiceStatus {
  name: string
  status: 'healthy' | 'degraded' | 'offline'
  uptime: number
  latency: number
  lastCheck: Date
  metrics: Record<string, unknown>
}

export interface IApiResponse<T> {
  success: boolean
  data?: T
  error?: {
    code: string
    message: string
    details?: unknown
  }
  metadata?: {
    timestamp: Date
    requestId: string
    version: string
  }
}

export interface IPagedResponse<T> {
  items: T[]
  total: number
  page: number
  pageSize: number
  hasMore: boolean
}

// Error types
export class PortalError extends Error {
  constructor(
    public code: string,
    message: string,
    public statusCode: number = 500,
    public details?: unknown
  ) {
    super(message)
    this.name = 'PortalError'
  }
}

// Event types
export interface IEvent {
  id: string
  type: string
  timestamp: Date
  source: string
  data: Record<string, unknown>
  userId?: string
}

export interface IEventListener {
  (event: IEvent): void | Promise<void>
}
