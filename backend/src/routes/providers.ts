/**
 * Multi-Cloud Sync Providers REST API Routes
 * 
 * Endpoints for managing cloud providers, credentials, synchronization,
 * and orchestration through a RESTful interface.
 */

import { Router, Request, Response } from 'express';
import { CloudProvider, SyncConfig } from '../providers/types';
import { ProviderFactory, MultiCloudProviderManager } from '../providers/registry';
import { SyncOrchestrator } from '../providers/sync-orchestrator';
import { CredentialManagerFactory } from '../providers/credential-manager';

const router = Router();

// Initialize components
const credentialManager = CredentialManagerFactory.create({
  gsmProjectId: process.env.GCP_PROJECT_ID,
  vaultAddr: process.env.VAULT_ADDR,
  vaultToken: process.env.VAULT_TKN,
  kmsKeyId: process.env.KMS_KEY_ID,
  auditLogDir: '.sync_audit',
});

const registry = ProviderFactory.initializeDefaultRegistry('.providers_audit');
const manager = new MultiCloudProviderManager(registry);
const orchestrator = new SyncOrchestrator(registry, '.sync_audit');

/**
 * GET /api/v1/providers
 * List all available cloud providers
 */
router.get('/providers', async (req: Request, res: Response) => {
  try {
    const allProviders = registry.getAll();
    const providers = allProviders.map(p => ({
      provider: p.provider,
      region: p.region,
      initialized: p.isInitialized(),
    }));

    res.json({
      success: true,
      data: providers,
      count: providers.length,
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : String(error),
    });
  }
});

/**
 * GET /api/v1/providers/:provider
 * Get specific provider details
 */
router.get('/providers/:provider', async (req: Request, res: Response) => {
  try {
    const provider = req.params.provider as CloudProvider;
    const instance = registry.get(provider);

    if (!instance) {
      return res.status(404).json({
        success: false,
        error: `Provider ${provider} not found`,
      });
    }

    const health = await instance.healthCheck();
    const audit = (instance as any).getAuditLog ? (instance as any).getAuditLog() : [];
    const stats = (instance as any).getAuditStats ? (instance as any).getAuditStats() : { total: 0, successful: 0, failed: 0, byOperation: {} };

    res.json({
      success: true,
      data: {
        provider: instance.provider,
        region: instance.region,
        initialized: instance.isInitialized(),
        health,
        stats,
        auditLogEntries: audit.length,
      },
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : String(error),
    });
  }
});

/**
 * POST /api/v1/providers/:provider/initialize
 * Initialize provider with credentials
 */
router.post('/providers/:provider/initialize', async (req: Request, res: Response) => {
  try {
    const provider = req.params.provider as CloudProvider;
    const { credentials } = req.body;

    if (!credentials) {
      return res.status(400).json({
        success: false,
        error: 'Credentials required',
      });
    }

    const instance = registry.get(provider);
    if (!instance) {
      return res.status(404).json({
        success: false,
        error: `Provider ${provider} not found`,
      });
    }

    const result = await instance.initialize({
      provider,
      ...credentials,
    });

    res.json({
      success: result.success,
      data: result.success ? { provider, initialized: true } : undefined,
      error: result.error,
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : String(error),
    });
  }
});

/**
 * POST /api/v1/providers/health-check
 * Check health of all providers
 */
router.post('/providers/health-check', async (req: Request, res: Response) => {
  try {
    const results = await manager.healthCheckAll();

    const healthy = results.filter(r => r.healthy).length;
    const total = results.length;

    res.json({
      success: true,
      data: {
        healthy,
        total,
        results,
        timestamp: new Date().toISOString(),
      },
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : String(error),
    });
  }
});

/**
 * POST /api/v1/sync
 * Start synchronization of resources
 */
router.post('/sync', async (req: Request, res: Response) => {
  try {
    const config: SyncConfig = req.body;

    if (!config.sourceProvider || !config.targetProviders || !config.resources) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields: sourceProvider, targetProviders, resources',
      });
    }

    const result = await orchestrator.sync(config);

    res.json({
      success: result.failedResources === 0,
      data: result,
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : String(error),
    });
  }
});

/**
 * GET /api/v1/sync/operations
 * List all sync operations
 */
router.get('/sync/operations', async (req: Request, res: Response) => {
  try {
    const operations = orchestrator.getSyncOperations();
    const stats = orchestrator.getStatistics();

    res.json({
      success: true,
      data: {
        operations,
        statistics: stats,
      },
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : String(error),
    });
  }
});

/**
 * GET /api/v1/sync/audit-log
 * Get sync audit log
 */
router.get('/sync/audit-log', async (req: Request, res: Response) => {
  try {
    const { operation, provider } = req.query;
    const auditLog = orchestrator.getAuditLog({
      operation: operation as string,
      provider: provider as unknown as CloudProvider,
    });

    res.json({
      success: true,
      data: {
        entries: auditLog,
        count: auditLog.length,
      },
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : String(error),
    });
  }
});

/**
 * POST /api/v1/credentials/fetch
 * Fetch credentials for a provider (with multi-layer fallback)
 */
router.post('/credentials/fetch', async (req: Request, res: Response) => {
  try {
    const { provider, sources } = req.body;

    if (!provider || !sources) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields: provider, sources',
      });
    }

    const credentials = await credentialManager.getCredentials(provider, sources);

    res.json({
      success: true,
      data: {
        provider,
        fetched: true,
        timestamp: new Date().toISOString(),
      },
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : String(error),
    });
  }
});

/**
 * POST /api/v1/credentials/rotate
 * Rotate credentials
 */
router.post('/credentials/rotate', async (req: Request, res: Response) => {
  try {
    const { provider, sources, newCredentials } = req.body;

    if (!provider || !sources || !newCredentials) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields: provider, sources, newCredentials',
      });
    }

    await credentialManager.rotateCredentials(provider, sources, newCredentials);

    res.json({
      success: true,
      data: {
        provider,
        rotated: true,
        timestamp: new Date().toISOString(),
      },
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : String(error),
    });
  }
});

/**
 * GET /api/v1/credentials/audit-log
 * Get credential audit log
 */
router.get('/credentials/audit-log', async (req: Request, res: Response) => {
  try {
    const { provider, operation } = req.query;
    const auditLog = await credentialManager.getAuditLog(
      provider as CloudProvider,
      operation as string,
    );

    res.json({
      success: true,
      data: {
        entries: auditLog,
        count: auditLog.length,
      },
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : String(error),
    });
  }
});

/**
 * GET /api/v1/status
 * Get overall system status
 */
router.get('/status', async (req: Request, res: Response) => {
  try {
    const healthResults = await manager.healthCheckAll();
    const syncStats = orchestrator.getStatistics();
    const credStarts = credentialManager.getStats();

    const healthy = healthResults.filter(r => r.healthy).length;

    res.json({
      success: true,
      data: {
        timestamp: new Date().toISOString(),
        providers: {
          total: healthResults.length,
          healthy,
          unhealthy: healthResults.length - healthy,
          details: healthResults,
        },
        sync: syncStats,
        credentials: credStarts,
      },
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : String(error),
    });
  }
});

/**
 * POST /api/v1/cleanup
 * Cleanup all resources
 */
router.post('/cleanup', async (req: Request, res: Response) => {
  try {
    await manager.cleanupAll();
    await credentialManager.cleanup();

    res.json({
      success: true,
      data: {
        message: 'All resources cleaned up',
        timestamp: new Date().toISOString(),
      },
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : String(error),
    });
  }
});

export default router;
