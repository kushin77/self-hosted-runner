import type { IProduct } from '@nexus/core'

export const OPS_PRODUCT: IProduct = {
  id: 'ops',
  name: 'NexusShield OPS',
  description: 'Enterprise operations management platform for deployments, secrets, and observability',
  status: 'active',
  version: '1.0.0',
  icon: '⚙️',
  features: [
    'deployment-management',
    'secrets-management',
    'observability-dashboard',
    'infrastructure-management',
    'log-streaming',
    'alert-management',
    'health-monitoring'
  ],
  apiUrl: '/api/v1/ops',
  permissions: [
    'read:deployments',
    'write:deployments',
    'read:secrets',
    'write:secrets',
    'read:observability',
    'read:infrastructure',
    'manage:alerts'
  ]
}

/**
 * OPS Product Module Manager
 */
export class OpsProduct {
  static getProduct(): IProduct {
    return OPS_PRODUCT
  }

  static getFeatures(): string[] {
    return OPS_PRODUCT.features
  }

  static hasFeature(feature: string): boolean {
    return OPS_PRODUCT.features.includes(feature)
  }

  static getPermissions(): string[] {
    return OPS_PRODUCT.permissions
  }

  static canPerformAction(permission: string, userPermissions: string[]): boolean {
    return userPermissions.includes(permission) || userPermissions.includes('admin:*')
  }
}
