const path = require('path');
const fs = require('fs');
const RetryStrategy = require('../strategies/retry');
const TimeoutIncreaseStrategy = require('../strategies/timeout-increase');
const AuditLog = require('./audit-log');
const ApprovalEngine = require('./approval-engine');
const winston = require('winston');

const logger = winston.createLogger({
  level: 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json()
  ),
  transports: [new winston.transports.Console()]
});

// Note: DB adapters (sqlite, postgres) are optional for MVP
// For production, implement persistent storage via ./db or ./pg_db
let db = null;

// Persistence for repair proposals (NDJSON)
const DATA_DIR = path.resolve(__dirname, '..', 'data');
const PROPOSALS_FILE = path.join(DATA_DIR, 'repair-proposals.ndjson');

async function ensureDataDir() {
  try {
    await fs.promises.mkdir(DATA_DIR, { recursive: true });
  } catch (e) {
    // ignore
  }
}

async function persistProposal(obj) {
  // If configured, persist to durable DB
  if (process.env.REPAIR_USE_DB === 'true') {
    try {
      await db.saveProposal(obj);
      return;
    } catch (e) {
      logger.warn('[DB] failed to save proposal, falling back to NDJSON', { err: e.message });
    }
  }
  await ensureDataDir();
  const line = JSON.stringify(obj) + '\n';
  await fs.promises.appendFile(PROPOSALS_FILE, line, { encoding: 'utf8' });
}

async function readAllProposals() {
  if (process.env.REPAIR_USE_DB === 'true') {
    try {
      return await db.listProposals();
    } catch (e) {
      logger.warn('[DB] failed to read proposals, falling back to NDJSON', { err: e.message });
    }
  }

  try {
    const content = await fs.promises.readFile(PROPOSALS_FILE, 'utf8');
    return content
      .split('\n')
      .filter(Boolean)
      .map(l => JSON.parse(l));
  } catch (e) {
    return [];
  }
}

/**
 * Autonomous Pipeline Repair Engine (MVP)
 */
class RepairService {
  constructor(config = {}) {
    this.config = config;
    this.strategies = [
      new RetryStrategy(),
      new TimeoutIncreaseStrategy()
    ];
    this.approvalThreshold = config.threshold || 0.7;
    this.auditLog = new AuditLog(config.auditConfig || {});
    this.approvalEngine = new ApprovalEngine({ threshold: this.approvalThreshold });
  }

  /**
   * Analyze a failure event and identify repair strategies
   */
  async analyze(event) {
    logger.info(`[REPAIR] analyzing failure event...`, { eventId: event.id, errMsg: event.errorMessage });

    const assessments = this.strategies.map(strategy => ({
      strategy: strategy.name,
      score: strategy.assess(event)
    }));

    const topStrategy = assessments.filter(a => a.score > 0).sort((a,b) => b.score - a.score)[0];

    if (!topStrategy) {
      logger.warn(`[REPAIR] No suitable strategy found for: ${event.errorMessage}`);
      this.auditLog.logAnalysis(event.id, event, { status: 'NO_STRATEGY' });
      return { status: 'NO_STRATEGY', message: 'No applicable repair strategy found' };
    }

    logger.info(`[REPAIR] Top strategy identified: ${topStrategy.strategy} (score: ${topStrategy.score})`);
    const strategy = this.strategies.find(s => s.name === topStrategy.strategy);
    const recommendation = await strategy.execute(event);

    const result = {
      status: 'REPAIR_IDENTIFIED',
      confidence: topStrategy.score,
      recommendedAction: recommendation.action,
      strategy: recommendation.strategy,
      risk: recommendation.risk,
      parameters: recommendation.parameters,
      requiresApproval: this.approvalEngine.requiresApproval(recommendation, topStrategy.score),
      recommendation
    };

    // Log analysis
    this.auditLog.logAnalysis(event.id, event, result);

    // Build a repair proposal object and persist it (NDJSON) for telemetry and audit
    const proposal = {
      proposalId: `rp-${Date.now()}-${event.id}`,
      eventId: event.id,
      createdAt: new Date().toISOString(),
      confidence: result.confidence,
      risk: result.risk,
      requiresApproval: result.requiresApproval,
      recommendedAction: result.recommendedAction,
      strategy: result.strategy,
      parameters: result.parameters,
      rawRecommendation: result.recommendation,
      sourceEvent: event
    };

    try {
      await persistProposal(proposal);
      logger.info('[TELEMETRY] repair.proposal.created', { proposalId: proposal.proposalId, eventId: event.id, risk: proposal.risk });
    } catch (e) {
      logger.error('[TELEMETRY_ERROR] failed to persist proposal', { error: e.message });
    }

    // Request approval if needed
    if (result.requiresApproval) {
      const approvalRequest = await this.approvalEngine.requestApproval(
        event.id,
        event,
        recommendation,
        `High-risk repair requires approval: ${recommendation.action} (risk: ${recommendation.risk})`
      );
      result.approvalRequired = true;
      result.approvalRequestId = approvalRequest.id;
      // Update persisted proposal with approval id
      try {
        const update = Object.assign({}, proposal, { approvalRequestId: approvalRequest.id });
        await persistProposal(Object.assign({ updateFor: proposal.proposalId }, update));
      } catch (e) {
        logger.warn('[TELEMETRY] failed to persist approval update', { err: e.message });
      }
    }

    return result;
  }

  /**
   * Execute an approved repair action
   */
  async executeRepair(eventId, approvalId = null) {
    // If approval was required, verify it was approved
    if (approvalId && !this.approvalEngine.isApproved(eventId)) {
      const status = this.approvalEngine.getApprovalStatus(eventId);
      if (status.status !== 'APPROVED') {
        throw new Error(`Approval required but not granted for event ${eventId}`);
      }
    }

    logger.info(`[REPAIR] executing repair for event ${eventId}`);
    
    // In real implementation, this would execute the repair action
    // For MVP, log the execution decision
    const result = {
      status: 'REPAIR_EXECUTED',
      eventId,
      executedAt: new Date().toISOString(),
      message: 'Repair action executed (MVP simulation)'
    };

    this.auditLog.logExecution(eventId, {}, result);

    // Persist execution telemetry
    try {
      await persistProposal({ executionFor: eventId, executedAt: result.executedAt, result });
      logger.info('[TELEMETRY] repair.execution.recorded', { eventId, executedAt: result.executedAt });
    } catch (e) {
      logger.error('[TELEMETRY_ERROR] failed to persist execution', { error: e.message });
    }
    return result;
  }

  /**
   * Get strategies available in this service
   */
  getStrategies() {
    return this.strategies.map(s => ({
      name: s.name,
      class: s.constructor.name
    }));
  }
}

// Export
module.exports = RepairService;

// Demo/self-test (single block)
if (require.main === module) {
  const service = new RepairService();
  const testEvents = [
    {
      id: 'evt-timeout-1',
      errorMessage: 'Error: Connection timeout after 30s',
      attemptNumber: 1
    },
    {
      id: 'evt-timeout-2',
      errorMessage: 'Request timed out after 5000ms while connecting to database',
      attemptNumber: 2
    },
    {
      id: 'evt-retry-1',
      errorMessage: 'Error: socket hangup',
      attemptNumber: 1
    }
  ];

  (async () => {
    logger.info('[DEMO] Running pipeline repair MVP self-test');
    for (const event of testEvents) {
      try {
        const result = await service.analyze(event);
        logger.info('[DEMO_RESULT]', { eventId: event.id, ...result });
      } catch (err) {
        logger.error('[DEMO_ERROR]', { eventId: event.id, error: err.message });
      }
    }

    // show persisted proposals count
    try {
      const proposals = await readAllProposals();
      logger.info('[DEMO] persisted proposals count', { count: proposals.length });
    } catch (e) {
      logger.warn('[DEMO] failed to read persisted proposals', { err: e.message });
    }
  })();
}
