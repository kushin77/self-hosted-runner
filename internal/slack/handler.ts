import { Request, Response } from 'express';
import crypto from 'crypto';
import { App, BlockAction, SlashCommand } from '@slack/bolt';
import { Pool } from 'pg';

export interface SlackContext {
  app: App;
  pool: Pool;
  signingSecret: string;
}

/**
 * Verify Slack request signature
 * Prevents replay attacks and spoofing
 */
export function verifySlackSignature(
  req: Request,
  signingSecret: string
): boolean {
  const timestamp = req.headers['x-slack-request-timestamp'];
  const signature = req.headers['x-slack-signature'];

  if (!timestamp || !signature) {
    return false;
  }

  // Verify timestamp is within 5 minutes
  const now = Math.floor(Date.now() / 1000);
  const requestTime = parseInt(timestamp as string, 10);
  if (Math.abs(now - requestTime) > 300) {
    console.warn('Slack request timestamp outside 5-minute window');
    return false;
  }

  // Compute signature
  const body = (req as any).rawBody || '';
  const baseString = `v0:${timestamp}:${body}`;
  const hmac = crypto.createHmac('sha256', signingSecret);
  hmac.update(baseString);
  const expectedSignature = 'v0=' + hmac.digest('hex');

  // Timing-safe comparison
  return crypto.timingSafeEqual(
    Buffer.from(signature as string),
    Buffer.from(expectedSignature)
  );
}

/**
 * Handle /nexus status command
 * Returns pipeline statistics for last 24 hours
 */
export async function handleNexusStatusCommand(
  command: SlashCommand,
  ctx: SlackContext
): Promise<string> {
  const tenantId = command.user_id; // Map Slack user to tenant

  try {
    // Query stats for last 24 hours
    const resultStats = await ctx.pool.query(
      `
        SELECT
          COUNT(*) as total_runs,
          SUM(CASE WHEN status = 1 THEN 1 ELSE 0 END) as success_count,
          SUM(CASE WHEN status = 4 THEN 1 ELSE 0 END) as failure_count,
          SUM(CASE WHEN status = 2 THEN 1 ELSE 0 END) as running_count
        FROM discovery_pipeline_runs
        WHERE tenant_id = $1 AND started_at > NOW() - INTERVAL '24 hours'
      `,
      [tenantId]
    );

    const stats = resultStats.rows[0];
    const totalRuns = parseInt(stats.total_runs || '0', 10);
    const successCount = parseInt(stats.success_count || '0', 10);
    const failureCount = parseInt(stats.failure_count || '0', 10);
    const runningCount = parseInt(stats.running_count || '0', 10);

    const successRate = totalRuns > 0 ? ((successCount / totalRuns) * 100).toFixed(1) : '0';

    // Get recent failures
    const failures = await ctx.pool.query(
      `
        SELECT id, repo, branch, commit_sha, ended_at
        FROM discovery_pipeline_runs
        WHERE tenant_id = $1 AND status = 4 AND started_at > NOW() - INTERVAL '24 hours'
        ORDER BY ended_at DESC
        LIMIT 3
      `,
      [tenantId]
    );

    // Format response blocks
    const blocks: any[] = [
      {
        type: 'section',
        text: {
          type: 'mrkdwn',
          text: `*NEXUS Pipeline Status (Last 24h)*\n✅ ${successCount} passed | ❌ ${failureCount} failed | ⏳ ${runningCount} running`,
        },
      },
      {
        type: 'section',
        text: {
          type: 'mrkdwn',
          text: `*Success Rate:* ${successRate}% | *Total Runs:* ${totalRuns}`,
        },
      },
    ];

    if (failures.rows.length > 0) {
      const failureText = failures.rows
        .map(
          (r) =>
            `• ${r.repo}@${r.branch.substring(0, 8)} (${new Date(r.ended_at).toLocaleTimeString()})`
        )
        .join('\n');

      blocks.push({
        type: 'section',
        text: {
          type: 'mrkdwn',
          text: `*Recent Failures:*\n${failureText}`,
        },
      });
    }

    // Send blocks
    await ctx.app.client.chat.postMessage({
      channel: command.channel_id,
      thread_ts: command.trigger_id,
      blocks,
      text: 'NEXUS Pipeline Status',
    });

    return 'Status command processed';
  } catch (err) {
    console.error('Error processing Slack command:', err);
    throw err;
  }
}

/**
 * Handle /nexus recent command
 * Shows recent pipeline failures with error analysis
 */
export async function handleNexusRecentCommand(
  command: SlashCommand,
  ctx: SlackContext
): Promise<string> {
  const tenantId = command.user_id;

  try {
    const result = await ctx.pool.query(
      `
        SELECT id, repo, branch, commit_sha, duration_ms, triggered_by
        FROM discovery_pipeline_runs
        WHERE tenant_id = $1 AND status = 4
        ORDER BY started_at DESC
        LIMIT 5
      `,
      [tenantId]
    );

    const blocks: any[] = [
      {
        type: 'header',
        text: {
          type: 'plain_text',
          text: '5 Recent Failures',
        },
      },
    ];

    for (const run of result.rows) {
      blocks.push({
        type: 'section',
        text: {
          type: 'mrkdwn',
          text: `*${run.repo}*\n_${run.branch}_ • ${(run.duration_ms / 1000).toFixed(1)}s • Triggered by: ${run.triggered_by}`,
        },
        accessory: {
          type: 'button',
          text: {
            type: 'plain_text',
            text: 'View Details',
          },
          action_id: `view_failure_${run.id}`,
          value: run.id,
        },
      });
    }

    await ctx.app.client.chat.postMessage({
      channel: command.channel_id,
      blocks,
      text: 'Recent Failures',
    });

    return 'Recent command processed';
  } catch (err) {
    console.error('Error processing recent command:', err);
    throw err;
  }
}

/**
 * Setup Slack handlers
 */
export function setupSlackHandlers(ctx: SlackContext): void {
  ctx.app.command('/nexus', async ({ ack, command }) => {
    await ack();

    const args = command.text.trim();

    try {
      if (args === 'status' || !args) {
        await handleNexusStatusCommand(command, ctx);
      } else if (args === 'recent') {
        await handleNexusRecentCommand(command, ctx);
      } else {
        ctx.app.client.chat.postEphemeral({
          channel: command.channel_id,
          user: command.user_id,
          text: 'Unknown command. Try: `/nexus status` or `/nexus recent`',
        });
      }
    } catch (err) {
      console.error('Error handling Slack command:', err);
      ctx.app.client.chat.postEphemeral({
        channel: command.channel_id,
        user: command.user_id,
        text: 'Error processing command. Please try again.',
      });
    }
  });

  // Handle button clicks for failure details
  ctx.app.action(/^view_failure_/, async ({ ack, action, body }) => {
    await ack();

    const blockAction = action as BlockAction;
    const runId = blockAction.value;

    // Query run details
    const result = await ctx.pool.query(
      `
        SELECT * FROM discovery_pipeline_runs WHERE id = $1
      `,
      [runId]
    );

    if (result.rows.length === 0) {
      return;
    }

    const run = result.rows[0];

    const blocks: any[] = [
      {
        type: 'section',
        text: {
          type: 'mrkdwn',
          text: `*${run.repo}*\nStatus: ${run.status}\nBranch: ${run.branch}\nCommit: \`${run.commit_sha.substring(0, 8)}\``,
        },
      },
      {
        type: 'section',
        text: {
          type: 'mrkdwn',
          text: `*Duration:* ${(run.duration_ms / 1000).toFixed(1)}s\n*Started:* ${new Date(run.started_at).toLocaleString()}`,
        },
      },
    ];

    await ctx.app.client.chat.postMessage({
      channel: (body as any).channel.id,
      thread_ts: (body as any).trigger_id,
      blocks,
      text: 'Failure Details',
    });
  });
}
