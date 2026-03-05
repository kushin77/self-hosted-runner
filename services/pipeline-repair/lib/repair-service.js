const RetryStrategy = require('../strategies/retry');
const TimeoutIncreaseStrategy = require('../strategies/timeout-increase');
const ApprovalEngine = require('./approval-engine');
const SafetyChecker = require('./safety-checker');
const approvalsStore = require('./approvals');
const winston = require('winston');

const logger = winston.createLogger({
  level: 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json()
  ),
  transports: [new winston.transports.Console()]
});

/**
 * Autonomous Pipeline Repair Engine (MVP)
 * Detects failures and recommends repair actions
 */
class RepairService {
  constructor(config = {}) {
    this.config = config;
    this.strategies = [
      new RetryStrategy(),
      new TimeoutIncreaseStrategy()
    ];
    this.approvalThreshold = config.threshold || 0.7; // Confidence score to auto-repair
    this.safety = new SafetyChecker(config.safety || {});
    this.approvalEngine = new ApprovalEngine({ threshold: config.approvalThreshold || 0.7 });
  }

  /**
   * Get all registered strategies
   * @returns {Array} Registered strategies
   */
  getStrategies() {
    return this.strategies;
  }

  /**
   * Process failure event and find repair strategies
   * @param {Object} event - Failure event context
   * @returns {Promise<Object>} Repair recommendation
   */
  async analyze(event) {
    logger.info(`[REPAIR] analyzing failure event...`, { eventId: event.id, errMsg: event.errorMessage });
    
    // Assess all strategies (support async assess functions and errors)
    const assessments = await Promise.all(this.strategies.map(async strategy => {
      try {
        const raw = typeof strategy.assess === 'function' ? await strategy.assess(event) : 0;
        const score = Number(raw) || 0;
        return { strategy: strategy.name, score, strategyRef: strategy };
      } catch (err) {
        logger.error('[REPAIR] strategy assess failed', { strategy: strategy.name, err: err && err.message });
        return { strategy: strategy.name, score: 0, strategyRef: strategy };
      }
    }));

    // Sort and filter top strategy
    const topStrategy = assessments
      .filter(a => a.score > 0)
      .sort((a, b) => b.score - a.score)[0];
      
    if (!topStrategy) {
      logger.warn(`[REPAIR] No suitable strategy found for: ${event.errorMessage}`);
      return { status: 'NO_STRATEGY' };
    }
    
    logger.info(`[REPAIR] Top strategy identified: ${topStrategy.strategy} (score: ${topStrategy.score})`);

    // Use resolved strategy reference (from assessment) or fallback by name
    const strategy = topStrategy.strategyRef || this.strategies.find(s => s.name === topStrategy.strategy);
    // Map strategy to an action type expected by SafetyChecker
    let actionType = 'repair_action';
    if ((strategy.name || '').toLowerCase().includes('timeout')) actionType = 'increase_timeout';
    else if ((strategy.name || '').toLowerCase().includes('retry')) actionType = 'status_check';

    const action = {
      id: `act-${event.id}-${Date.now()}`,
      type: actionType,
      scope: event.scope || 'pipeline-repair-service',
      description: `Execute strategy ${strategy.name} for event ${event.id}`,
      currentCount: event.currentCount,
      targetCount: event.targetCount,
      estimatedCostDelta: strategy.estimatedCostDelta || 0
    };

    // Run safety checks before executing any repair
    const safetyResult = await this.safety.checkSafety(action, { baseline: event.baseline || {} });

    if (!safetyResult.safe) {
      // If RED or violations exist, do not proceed; request approval if YELLOW
      logger.warn('[REPAIR] Safety check blocked execution', { eventId: event.id, safety: safetyResult });
      if (safetyResult.category === 'YELLOW') {
        // create approval request and persist
        const req = await this.approvalEngine.requestApproval(event.id, event, action, safetyResult.recommendation);
        approvalsStore.requestApproval(event.id, req).catch(err => logger.error('approval persist failed', err.message));
        return {
          status: 'PENDING_APPROVAL',
          confidence: topStrategy.score,
          safety: safetyResult,
          approvalRequest: req
        };
      }

      return {
        status: 'BLOCKED_BY_SAFETY',
        confidence: topStrategy.score,
        safety: safetyResult
      };
    }

    // If safe and GREEN or approved, execute the recommendation
    const recommendation = await strategy.execute(event);

    // If approved, persist approval record
    if (approvalsStore.hasApproval(event.id)) {
      approvalsStore.addApproval(event.id, { request: { eventId: event.id, approvedAt: new Date().toISOString() }, status: 'APPROVED' });
    }

    return {
      status: 'REPAIR_IDENTIFIED',
      confidence: topStrategy.score,
      requiresApproval: topStrategy.score < this.approvalThreshold,
      risk: topStrategy.score > 0.8 ? 'LOW' : 'MEDIUM',
      recommendation,
      safety: safetyResult
    };
  }
}

module.exports = RepairService;

if (require.main === module) {
  const service = new RepairService();
  const sampleEvent = {
    id: 'evt-1234',
    errorMessage: 'Error: Connection timeout after 30s',
    attemptNumber: 1
  };
  
  service.analyze(sampleEvent)
    .then(rec => logger.info('[REPAIR_RECOMMENDATION]', rec))
    .catch(err => logger.error('[REPAIR_FAILED]', err));
}
