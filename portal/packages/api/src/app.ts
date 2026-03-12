import express, { Application, Request, Response, NextFunction } from 'express'
import cors from 'cors'
import { logger, IApiResponse, PortalError, API_VERSION } from '@nexus/core'

/**
 * Express application factory
 */
export function createApp(): Application {
  const app = express()

  // Middleware
  app.use(cors())
  app.use(express.json({ limit: '50mb' }))
  app.use(express.urlencoded({ limit: '50mb', extended: true }))

  // Request logging
  app.use((req: Request, res: Response, next: NextFunction) => {
    const start = Date.now()
    res.on('finish', () => {
      const duration = Date.now() - start
      logger.info({
        method: req.method,
        path: req.path,
        status: res.statusCode,
        duration: `${duration}ms`
      })
    })
    next()
  })

  // Health check
  app.get('/health', (req: Request, res: Response) => {
    const response: IApiResponse<{ status: string; timestamp: string; version: string }> = {
      success: true,
      data: {
        status: 'healthy',
        timestamp: new Date().toISOString(),
        version: API_VERSION
      }
    }
    res.json(response)
  })

  // API version endpoint
  app.get('/api/version', (req: Request, res: Response) => {
    const response: IApiResponse<{ version: string }> = {
      success: true,
      data: { version: API_VERSION }
    }
    res.json(response)
  })

  // Products endpoint
  app.get('/api/v1/products', (req: Request, res: Response) => {
    const products = [
      {
        id: 'ops',
        name: 'NexusShield OPS',
        description: 'Operations management platform',
        status: 'active',
        version: '1.0.0',
        icon: '⚙️',
        features: ['deployment', 'secrets', 'observability'],
        apiUrl: '/api/v1/ops',
        permissions: ['read:deployments', 'write:deployments', 'read:secrets']
      },
      {
        id: 'security',
        name: 'NexusShield Security',
        description: 'Security and compliance suite',
        status: 'future',
        version: '0.0.0',
        icon: '🔒',
        features: ['sast', 'dast', 'compliance'],
        apiUrl: '/api/v1/security',
        permissions: []
      }
    ]

    const response: IApiResponse<typeof products> = {
      success: true,
      data: products,
      metadata: {
        timestamp: new Date(),
        requestId: `req-${Date.now()}`,
        version: API_VERSION
      }
    }
    res.json(response)
  })

  // OPS endpoints
  app.get('/api/v1/ops/deployments', (req: Request, res: Response) => {
    const deployments = [
      {
        id: 'deploy-001',
        name: 'Backend v1.2.3',
        environment: 'production',
        status: 'success',
        version: 'v1.2.3',
        startTime: new Date(Date.now() - 3600000),
        endTime: new Date(Date.now() - 3000000),
        duration: 600,
        logs: '',
        deployedBy: 'github-actions',
        metadata: {}
      }
    ]

    const response: IApiResponse<typeof deployments> = {
      success: true,
      data: deployments
    }
    res.json(response)
  })

  // Error handling middleware
  app.use((err: unknown, req: Request, res: Response, next: NextFunction) => {
    if (err instanceof PortalError) {
      logger.error({
        code: err.code,
        message: err.message,
        statusCode: err.statusCode
      })
      const response: IApiResponse<null> = {
        success: false,
        error: {
          code: err.code,
          message: err.message,
          details: err.details
        }
      }
      res.status(err.statusCode).json(response)
    } else {
      logger.error({ error: err })
      const response: IApiResponse<null> = {
        success: false,
        error: {
          code: 'INTERNAL_ERROR',
          message: 'An unexpected error occurred'
        }
      }
      res.status(500).json(response)
    }
  })

  // 404 handler
  app.use((req: Request, res: Response) => {
    const response: IApiResponse<null> = {
      success: false,
      error: {
        code: 'NOT_FOUND',
        message: `Endpoint ${req.method} ${req.path} not found`
      }
    }
    res.status(404).json(response)
  })

  return app
}
