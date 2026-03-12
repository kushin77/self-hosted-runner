import type { IProduct } from '@nexus/core'

/**
 * Security Product Definition (Future)
 */
export const SECURITY_PRODUCT: IProduct = {
  id: 'security',
  name: 'NexusShield Security Suite',
  description: 'Comprehensive security and compliance management platform',
  status: 'future',
  version: '0.0.1',
  icon: '🔒',
  features: [
    'sast-scanning',
    'dast-scanning',
    'dependency-scanning',
    'container-scanning',
    'compliance-management',
    'vulnerability-tracking',
    'policy-enforcement'
  ],
  apiUrl: '/api/v1/security',
  permissions: [
    'read:vulnerabilities',
    'read:compliance',
    'write:policies',
    'manage:security'
  ]
}

export class SecurityProduct {
  static getProduct(): IProduct {
    return SECURITY_PRODUCT
  }

  static getFeatures(): string[] {
    return SECURITY_PRODUCT.features
  }

  static isAvailable(): boolean {
    return SECURITY_PRODUCT.status === 'active' || SECURITY_PRODUCT.status === 'beta'
  }
}
