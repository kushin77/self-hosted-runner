const RetryStrategy = require('../strategies/retry');
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
 */
class RepairService {
  constructor(config = {}) {
    this.config = config;
    this.strategies = [new RetryStrategy()];
    this.approvalThreshold = config.threshold || 0.7;
  }

  async analyze(event) {
    logger.info(`[REPAIR] analyzing failure event...`, { eventId: event.id, errMsg: event.errorMessage });

    const assessments = this.strategies.map(strategy => ({
      strategy: strategy.name,
      score: strategy.assess(event)
    }));

    const topStrategy = assessments.filter(a => a.score > 0).sort((a,b) => b.score - a.score)[0];

    if (!topStrategy) {
      logger.warn(`[REPAIR] No suitable strategy found for: ${event.errorMessage}`);
      return { status: 'NO_STRATEGY' };
    }

    logger.info(`[REPAIR] Top strategy identified: ${topStrategy.strategy} (score: ${topStrategy.score})`);
    const strategy = this.strategies.find(s => s.name === topStrategy.strategy);
    const recommendation = await strategy.execute(event);

    return {
      status: 'REPAIR_IDENTIFIED',
      confidence: topStrategy.score,
      requiresApproval: topStrategy.score < this.approvalThreshold,
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
