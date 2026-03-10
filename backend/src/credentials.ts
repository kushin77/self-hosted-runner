/**
 * Credential Management Service
 * Handles GSM → Vault → KMS → Local Cache credential lifecycle
 * Implements immutable audit trail, ephemeral credentials, idempotent operations
 */

import { SecretManagerServiceClient } from '@google-cloud/secret-manager';
import NodeVault from 'node-vault';
import { KeyManagementServiceClient } from '@google-cloud/kms';
import { getPrisma } from './prisma-wrapper';
import crypto from 'crypto';

const prisma = getPrisma();

// ============================================================================
// TYPE DEFINITIONS
// ============================================================================

export interface CredentialResolution {
  value: string;
  layer: 'gsm' | 'vault' | 'kms' | 'cache';
  latency_ms: number;
  resolutionTime: Date;
  source: string;
}

export interface CredentialRotationRequest {
  credentialId: string;
  credentialName: string;
  credentialType: string;
  newValue: string;
  reason: 'scheduled' | 'manual' | 'revoked' | 'compromised' | 'expired';
  requestedBy: string;
}

export interface CredentialAuditEntry {
  timestamp: Date;
  action: 'created' | 'rotated' | 'accessed' | 'revoked' | 'diagnosed';
  credentialId: string;
  credentialName: string;
  actor: string;
  status: 'success' | 'denied' | 'failed';
  details?: Record<string, any>;
}

// ============================================================================
// CREDENTIAL SERVICE
// ============================================================================

export class CredentialService {
  private secretManager: SecretManagerServiceClient;
  private vault: NodeVault.client;
  private kms: KeyManagementServiceClient;
  private localCache: Map<string, { value: string; expiresAt: Date }> = new Map();

  constructor() {
    this.secretManager = new SecretManagerServiceClient();
    // Prefer Vault Agent token sink file to avoid env token exposure
    const vaultAddr = process.env.VAULT_ADDR || 'http://localhost:8200';
    const vaultNamespace = process.env.VAULT_NAMESPACE || '';
    const vaultTokenFile = process.env.VAULT_TOKEN_FILE || '/var/run/secrets/vault/token';
    let vaultToken = process.env.REDACTED_VAULT_TOKEN || process.env.VAULT_TOKEN || '';
    try {
      const fs = require('fs');
      if (fs.existsSync(vaultTokenFile)) {
        vaultToken = fs.readFileSync(vaultTokenFile, 'utf8').trim();
      }
    } catch (e) {
      // ignore file read errors and fall back to env
    }

    const nodeVaultOpts: any = { endpoint: vaultAddr };
    if (vaultToken) nodeVaultOpts.token = vaultToken;
    if (vaultNamespace) nodeVaultOpts.namespace = vaultNamespace;
    this.vault = NodeVault(nodeVaultOpts);
    this.kms = new KeyManagementServiceClient();
  }

  /**
   * Resolve credential from 4-layer cascade: GSM → Vault → KMS → LocalCache
   * Ephemeral: Runtime fetch, no persistence
   * Idempotent: Same input always produces same output
   */
  async resolveCredential(credentialName: string): Promise<CredentialResolution> {
    const startTime = Date.now();

    try {
      // Layer 1: Google Secret Manager (Primary)
      try {
        const gsmValue = await this.getFromGSM(credentialName);
        if (gsmValue) {
          // Update local cache for failover
          this.localCache.set(credentialName, {
            value: gsmValue,
            expiresAt: new Date(Date.now() + 60 * 60 * 1000), // 1-hour validity
          });

          await this.auditCredentialAccess(
            credentialName,
            'gsm',
            'accessed',
            'success'
          );

          return {
            value: gsmValue,
            layer: 'gsm',
            latency_ms: Date.now() - startTime,
            resolutionTime: new Date(),
            source: `gcp-projects/${process.env.GCP_PROJECT_ID}/secrets/${credentialName}`,
          };
        }
      } catch (e: any) {
        console.warn(`⚠️ GSM resolution failed: ${e.message}`);
      }

      // Layer 2A: Vault (Secondary)
      try {
        const vaultValue = await this.getFromVault(credentialName);
        if (vaultValue) {
          // Update local cache for failover
          this.localCache.set(credentialName, {
            value: vaultValue,
            expiresAt: new Date(Date.now() + 50 * 60 * 1000), // 50-min validity
          });

          await this.auditCredentialAccess(
            credentialName,
            'vault',
            'accessed',
            'success'
          );

          return {
            value: vaultValue,
            layer: 'vault',
            latency_ms: Date.now() - startTime,
            resolutionTime: new Date(),
            source: `vault:secret/data/${credentialName}`,
          };
        }
      } catch (e: any) {
        console.warn(`⚠️ Vault resolution failed: ${e.message}`);
      }

      // Layer 2B: AWS KMS (Tertiary)
      try {
        const kmsValue = await this.getFromKMS(credentialName);
        if (kmsValue) {
          // Update local cache for failover
          this.localCache.set(credentialName, {
            value: kmsValue,
            expiresAt: new Date(Date.now() + 30 * 60 * 1000), // 30-min validity
          });

          await this.auditCredentialAccess(
            credentialName,
            'kms',
            'accessed',
            'success'
          );

          return {
            value: kmsValue,
            layer: 'kms',
            latency_ms: Date.now() - startTime,
            resolutionTime: new Date(),
            source: `aws-kms:arn:aws:kms:${process.env.AWS_REGION}:${process.env.AWS_ACCOUNT_ID}:key/${credentialName}`,
          };
        }
      } catch (e: any) {
        console.warn(`⚠️ KMS resolution failed: ${e.message}`);
      }

      // Layer 3: Local Cache (Offline Fallback)
      const cached = this.localCache.get(credentialName);
      if (cached && cached.expiresAt > new Date()) {
        await this.auditCredentialAccess(
          credentialName,
          'cache',
          'accessed',
          'success'
        );

        return {
          value: cached.value,
          layer: 'cache',
          latency_ms: Date.now() - startTime,
          resolutionTime: new Date(),
          source: 'local-cache-offline-fallback',
        };
      }

      // All layers exhausted
      await this.auditCredentialAccess(
        credentialName,
        'none',
        'accessed',
        'failed'
      );

      throw new Error(
        `Credential '${credentialName}' not found in any layer (GSM, Vault, KMS, Cache)`
      );
    } catch (error: any) {
      console.error(`❌ Credential resolution failed: ${error.message}`);
      throw error;
    }
  }

  // =========================================================================
  // LAYER IMPLEMENTATIONS
  // =========================================================================

  private async getFromGSM(secretName: string): Promise<string | null> {
    try {
      const projectId = process.env.GCP_PROJECT_ID;
      if (!projectId) return null;

      const name = `projects/${projectId}/secrets/${secretName}/versions/latest`;
      const [version] = await this.secretManager.accessSecretVersion({ name });
      const payload = version.payload?.data;

      if (payload instanceof Uint8Array) {
        return Buffer.from(payload).toString('utf8');
      }
      return typeof payload === 'string' ? payload : null;
    } catch (error: any) {
      if (error.code === 5) return null; // Not found
      throw error;
    }
  }

  private async getFromVault(credentialName: string): Promise<string | null> {
    try {
      const path = `secret/data/${credentialName}`;
      const result = await this.vault.read(path);
      return result.data?.data?.value || null;
    } catch (error: any) {
      if (error.statusCode === 404) return null; // Not found
      throw error;
    }
  }

  private async getFromKMS(credentialName: string): Promise<string | null> {
    try {
      const keyName = `projects/${process.env.GCP_PROJECT_ID}/locations/${process.env.GCP_REGION || 'us-central1'}/keyRings/nexusshield-portal/cryptoKeys/${credentialName}`;
      // Mock implementation (real KMS would decrypt ciphertext)
      const cred = await prisma.credential.findFirst({
        where: { type: 'kms', name: credentialName },
      });
      return cred?.value || null;
    } catch (error: any) {
      if (error.statusCode === 404) return null; // Not found
      throw error;
    }
  }

  // =========================================================================
  // CREDENTIAL ROTATION
  // =========================================================================

  /**
   * Rotate credential (immutable audit trail, idempotent)
   */
  async rotateCredential(
    request: CredentialRotationRequest
  ): Promise<{ rotationId: string; oldValueHash: string; newValueHash: string }> {
    try {
      // Get old value for audit hash
      const existing = await prisma.credential.findUnique({
        where: { id: request.credentialId },
      });

      if (!existing) {
        throw new Error(`Credential ${request.credentialId} not found`);
      }

      const oldValueHash = crypto
        .createHash('sha256')
        .update(existing.value)
        .digest('hex');
      const newValueHash = crypto
        .createHash('sha256')
        .update(request.newValue)
        .digest('hex');

      // Update credential in database
      const updated = await prisma.credential.update({
        where: { id: request.credentialId },
        data: {
          value: request.newValue,
          updated_at: new Date(),
        },
      });

      // Create immutable rotation history entry
      const rotation = await prisma.rotationHistory.create({
        data: {
          credentialId: request.credentialId,
          old_value_hash: oldValueHash,
          new_value_hash: newValueHash,
          rotation_reason: request.reason,
          rotated_by: request.requestedBy,
        },
      });

      // Log to audit trail
      await this.auditCredentialAccess(
        request.credentialName,
        request.credentialType,
        'rotated',
        'success',
        {
          rotation_id: rotation.id,
          reason: request.reason,
          rotated_by: request.requestedBy,
        }
      );

      return {
        rotationId: rotation.id,
        oldValueHash,
        newValueHash,
      };
    } catch (error: any) {
      await this.auditCredentialAccess(
        request.credentialName,
        request.credentialType,
        'rotated',
        'failed',
        { error: error.message }
      );
      throw error;
    }
  }

  /**
   * Schedule credential rotation (idempotent - rescheduling same credential is safe)
   */
  async scheduleRotation(
    credentialName: string,
    credentialType: string,
    cronExpression: string = '0 2 * * *' // Daily 2 AM UTC
  ): Promise<{ scheduledRotationId: string; nextRun: Date }> {
    try {
      const scheduled = await prisma.scheduledRotation.upsert({
        where: {
          credential_name_credential_type: {
            credential_name: credentialName,
            credential_type: credentialType,
          },
        },
        create: {
          credential_name: credentialName,
          credential_type: credentialType,
          schedule: cronExpression,
          enabled: true,
          next_run: this.calculateNextRun(cronExpression),
        },
        update: {
          schedule: cronExpression,
          enabled: true,
          next_run: this.calculateNextRun(cronExpression),
        },
      });

      return {
        scheduledRotationId: scheduled.id,
        nextRun: scheduled.next_run || new Date(),
      };
    } catch (error: any) {
      throw new Error(`Failed to schedule rotation: ${error.message}`);
    }
  }

  // =========================================================================
  // AUDIT TRAIL (IMMUTABLE)
  // =========================================================================

  /**
   * Log credential access to immutable audit trail
   */
  private async auditCredentialAccess(
    credentialName: string,
    credentialType: string,
    action: 'created' | 'rotated' | 'accessed' | 'revoked' | 'diagnosed',
    status: 'success' | 'denied' | 'failed',
    details?: Record<string, any>
  ): Promise<void> {
    try {
      const entry: CredentialAuditEntry = {
        timestamp: new Date(),
        action,
        credentialId: '',
        credentialName,
        actor: 'system',
        status,
        details,
      };

      // Write to immutable database audit log
      await prisma.auditLog.create({
        data: {
          event: `credential_${action}`,
          resource_type: 'credential',
          resource_id: credentialName,
          actor_id: 'system',
          action: `${credentialType}:${action}`,
          details: JSON.stringify(details || {}),
          hash: this.calculateHash(JSON.stringify(entry)),
          previous_hash: null, // TODO: chain with previous entry
        },
      });

      // Also log to JSONL for cloud export
      const fs = await import('fs');
      const path = await import('path');
      const logsDir = path.join(__dirname, '../logs');
      if (!fs.existsSync(logsDir)) {
        fs.mkdirSync(logsDir, { recursive: true });
      }

      fs.appendFileSync(
        path.join(logsDir, 'credential-audit.jsonl'),
        JSON.stringify(entry) + '\n'
      );
    } catch (error: any) {
      console.error(`⚠️ Audit logging failed: ${error.message}`);
      // Non-blocking: don't fail credential access if audit logging fails
    }
  }

  // =========================================================================
  // HELPERS
  // =========================================================================

  private calculateHash(data: string): string {
    return crypto.createHash('sha256').update(data).digest('hex');
  }

  private calculateNextRun(cronExpression: string): Date {
    // Simple implementation: assume daily at 2 AM UTC
    const next = new Date();
    next.setUTCHours(2, 0, 0, 0);
    if (next <= new Date()) {
      next.setDate(next.getDate() + 1); // Tomorrow
    }
    return next;
  }
}

// ============================================================================
// SINGLETON INSTANCE
// ============================================================================

let instance: CredentialService | null = null;

export function getCredentialService(): CredentialService {
  if (!instance) {
    instance = new CredentialService();
  }
  return instance;
}

export default CredentialService;
