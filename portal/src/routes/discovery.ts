import express, { Router, Request, Response, NextFunction } from 'express';
import { Pool, QueryResult } from 'pg';
import { z } from 'zod';

export interface DiscoveryContext {
  pool: Pool;
  tenantId: string;
  userId: string;
}

// ============================================================================
// Validation Schemas
// ============================================================================

const DiscoveryRunsQuerySchema = z.object({
  source: z.enum(['github', 'gitlab', 'jenkins', 'bitbucket']).optional(),
  status: z.enum(['success', 'failed', 'running', 'pending', 'cancelled']).optional(),
  limit: z.coerce.number().int().min(1).max(500).default(50),
  offset: z.coerce.number().int().min(0).default(0),
  since: z.string().datetime().optional(),
  repo: z.string().optional(),
  branch: z.string().optional(),
});

type DiscoveryRunsQuery = z.infer<typeof DiscoveryRunsQuerySchema>;

// ============================================================================
// Data Transfer Objects
// ============================================================================

export interface PipelineRun {
  id: string;
  source: string;
  repo: string;
  status: string;
  startedAt: string;
  endedAt: string;
  durationMs: number;
  branch: string;
  commitSha: string;
  triggeredBy: string;
}

export interface DiscoveryRunsResponse {
  runs: PipelineRun[];
  metadata: {
    total: number;
    pageSize: number;
    hasMore: boolean;
    offset: number;
  };
}

export interface DiscoveryStatsResponse {
  stats: {
    totalRuns: number;
    successCount: number;
    failureCount: number;
    runningCount: number;
    successRate: number;
    avgDurationMs: number;
    bySource: Record<string, {
      count: number;
      successCount: number;
      successRate: number;
    }>;
  };
}

// ============================================================================
// Middleware
// ============================================================================

/**
 * Extract tenant_id from JWT token and set for RLS enforcement
 */
export async function tenantMiddleware(
  req: Request,
  res: Response,
  next: NextFunction
) {
  const ctx = req.app.locals.discoveryContext as DiscoveryContext;
  
  // Extract tenant from authenticated JWT
  const tenantId = (req.user as any)?.tenant_id;
  if (!tenantId) {
    return res.status(401).json({ error: 'Missing tenant in token' });
  }

  // Set server-side session variable for RLS
  await ctx.pool.query('SET app.current_tenant_id = $1', [tenantId]);
  
  (req as any).context = {
    ...ctx,
    tenantId,
  };

  next();
}

// ============================================================================
// Endpoints
// ============================================================================

/**
 * GET /api/v1/discovery/runs
 * Query pipeline runs with optional filtering
 */
export async function getDiscoveryRuns(
  req: Request,
  res: Response
) {
  try {
    const query = DiscoveryRunsQuerySchema.parse(req.query);
    const ctx = (req as any).context as DiscoveryContext;

    // Build WHERE clause
    let whereClause = 'WHERE tenant_id = $1';
    let params: any[] = [ctx.tenantId];
    let paramIdx = 2;

    if (query.source) {
      whereClause += ` AND source = $${paramIdx}`;
      params.push(query.source);
      paramIdx++;
    }

    if (query.status) {
      whereClause += ` AND status = $${paramIdx}`;
      params.push(mapStatusToDb(query.status));
      paramIdx++;
    }

    if (query.since) {
      whereClause += ` AND started_at > $${paramIdx}`;
      params.push(new Date(query.since));
      paramIdx++;
    }

    if (query.repo) {
      whereClause += ` AND repo ILIKE $${paramIdx}`;
      params.push(`%${query.repo}%`);
      paramIdx++;
    }

    if (query.branch) {
      whereClause += ` AND branch = $${paramIdx}`;
      params.push(query.branch);
      paramIdx++;
    }

    // Count total
    const countResult = await ctx.pool.query(
      `SELECT COUNT(*) as total FROM discovery_pipeline_runs ${whereClause}`,
      params
    );
    const total = parseInt(countResult.rows[0].total, 10);

    // Fetch paginated results
    const result = await ctx.pool.query(
      `
        SELECT
          id, source, repo, status, started_at, ended_at, duration_ms,
          branch, commit_sha, triggered_by
        FROM discovery_pipeline_runs
        ${whereClause}
        ORDER BY started_at DESC
        LIMIT $${paramIdx} OFFSET $${paramIdx + 1}
      `,
      [...params, query.limit, query.offset]
    );

    const runs: PipelineRun[] = result.rows.map(row => ({
      id: row.id,
      source: row.source,
      repo: row.repo,
      status: row.status,
      startedAt: row.started_at.toISOString(),
      endedAt: row.ended_at.toISOString(),
      durationMs: row.duration_ms,
      branch: row.branch,
      commitSha: row.commit_sha,
      triggeredBy: row.triggered_by,
    }));

    const response: DiscoveryRunsResponse = {
      runs,
      metadata: {
        total,
        pageSize: runs.length,
        hasMore: query.offset + query.limit < total,
        offset: query.offset,
      },
    };

    res.json(response);
  } catch (err) {
    if (err instanceof z.ZodError) {
      return res.status(400).json({ error: 'Invalid query parameters', details: err.issues });
    }
    console.error('Error fetching runs:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
}

/**
 * GET /api/v1/discovery/stats
 * Get aggregated pipeline statistics
 */
export async function getDiscoveryStats(req: Request, res: Response) {
  try {
    const ctx = (req as any).context as DiscoveryContext;

    // Total stats
    const totalStats = await ctx.pool.query(
      `
        SELECT
          COUNT(*) as total_runs,
          SUM(CASE WHEN status = 1 THEN 1 ELSE 0 END) as success_count,
          SUM(CASE WHEN status = 4 THEN 1 ELSE 0 END) as failure_count,
          SUM(CASE WHEN status = 2 THEN 1 ELSE 0 END) as running_count,
          AVG(duration_ms)::bigint as avg_duration_ms
        FROM discovery_pipeline_runs
        WHERE tenant_id = $1
      `,
      [ctx.tenantId]
    );

    const stats = totalStats.rows[0];
    const successRate = stats.total_runs > 0 
      ? (stats.success_count / stats.total_runs) 
      : 0;

    // Stats by source
    const bySourceResult = await ctx.pool.query(
      `
        SELECT
          source,
          COUNT(*) as count,
          SUM(CASE WHEN status = 1 THEN 1 ELSE 0 END) as success_count
        FROM discovery_pipeline_runs
        WHERE tenant_id = $1
        GROUP BY source
      `,
      [ctx.tenantId]
    );

    const bySource: Record<string, any> = {};
    for (const row of bySourceResult.rows) {
      bySource[row.source] = {
        count: parseInt(row.count, 10),
        successCount: parseInt(row.success_count, 10),
        successRate: row.count > 0 ? (row.success_count / row.count) : 0,
      };
    }

    const response: DiscoveryStatsResponse = {
      stats: {
        totalRuns: parseInt(stats.total_runs, 10),
        successCount: parseInt(stats.success_count, 10),
        failureCount: parseInt(stats.failure_count, 10),
        runningCount: parseInt(stats.running_count, 10),
        successRate,
        avgDurationMs: parseInt(stats.avg_duration_ms, 10),
        bySource,
      },
    };

    res.json(response);
  } catch (err) {
    console.error('Error fetching stats:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
}

/**
 * GET /api/v1/discovery/runs/:id
 * Get detailed information about a specific run
 */
export async function getDiscoveryRunDetail(req: Request, res: Response) {
  try {
    const { id } = req.params;
    const ctx = (req as any).context as DiscoveryContext;

    const result = await ctx.pool.query(
      `
        SELECT
          id, source, repo, status, started_at, ended_at, duration_ms,
          branch, commit_sha, triggered_by, source_run_id
        FROM discovery_pipeline_runs
        WHERE id = $1 AND tenant_id = $2
      `,
      [id, ctx.tenantId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Run not found' });
    }

    const row = result.rows[0];
    const run: PipelineRun = {
      id: row.id,
      source: row.source,
      repo: row.repo,
      status: row.status,
      startedAt: row.started_at.toISOString(),
      endedAt: row.ended_at.toISOString(),
      durationMs: row.duration_ms,
      branch: row.branch,
      commitSha: row.commit_sha,
      triggeredBy: row.triggered_by,
    };

    res.json(run);
  } catch (err) {
    console.error('Error fetching run detail:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
}

// ============================================================================
// Helper Functions
// ============================================================================

function mapStatusToDb(status: string): number {
  const statusMap: Record<string, number> = {
    success: 1,
    running: 2,
    failed: 4,
    pending: 0,
    cancelled: 5,
  };
  return statusMap[status] || 0;
}

// ============================================================================
// Router Setup
// ============================================================================

export function createDiscoveryRouter(): Router {
  const router = express.Router();

  router.use(tenantMiddleware);

  router.get('/runs', getDiscoveryRuns);
  router.get('/runs/:id', getDiscoveryRunDetail);
  router.get('/stats', getDiscoveryStats);

  return router;
}
