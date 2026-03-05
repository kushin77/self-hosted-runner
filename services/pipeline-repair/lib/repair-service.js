const RetryStrategy = require('../strategies/retry');
const TimeoutIncreaseStrategy = require('../strategies/timeout-increase');
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
    
    // Assess all strategies (support async assess functions and handle errors)
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
    const strategy = (topStrategy && topStrategy.strategyRef) || this.strategies.find(s => s.name === (topStrategy && topStrategy.strategy));

    // Execute repair logic (in MVP, just return recommendation)
    const recommendation = strategy && typeof strategy.execute === 'function' ? await strategy.execute(event) : { action: 'NONE' };

    return {
      status: 'REPAIR_IDENTIFIED',
      confidence: topStrategy.score,
      requiresApproval: topStrategy.score < this.approvalThreshold,
      risk: topStrategy.score > 0.8 ? 'LOW' : 'MEDIUM',
      recommendation
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
