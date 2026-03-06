const RetryStrategy = require('../strategies/retry');
const TimeoutIncreaseStrategy = require('../strategies/timeout-increase');
const ResilientHttpClient = require('./http-client');
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
 * Autonomous Pipeline Repair Engine with Resilience
 * Detects failures, recommends repair actions, and executes with retry/timeout/circuit-breaker logic
 */
class RepairService {
  constructor(config = {}) {
    this.config = config;
    this.strategies = [
      new RetryStrategy(),
      new TimeoutIncreaseStrategy()
    ];
    this.approvalThreshold = typeof config.threshold === 'number' ? config.threshold : 0.7; // Confidence score to auto-repair
    
    // Initialize resilient HTTP client for downstream service calls
    this.httpClient = new ResilientHttpClient({
      maxAttempts: config.httpClient?.maxAttempts || 5,
      baseDelayMs: config.httpClient?.baseDelayMs || 2000,
      maxDelayMs: config.httpClient?.maxDelayMs || 30000,
      basicTimeoutMs: config.httpClient?.basicTimeoutMs || 10000,
      complexTimeoutMs: config.httpClient?.complexTimeoutMs || 30000,
      jitter: config.httpClient?.jitter !== false,
      circuitBreaker: config.circuitBreaker || {}
    });
    
    logger.info('[REPAIR_SERVICE] Initialized with resilient HTTP client', {
      approvalThreshold: this.approvalThreshold,
      strategies: this.strategies.map(s => s.name),
      httpClient: 'enabled'
    });
  }

  /**
   * Get all registered strategies
   * @returns {Array} Registered strategies
   */
  getStrategies() {
    return this.strategies;
  }

  /**
   * Execute repair action via HTTP call with resilience (retry, timeout, circuit breaker)
   * @param {Object} action - Repair action recommendation
   * @param {string} targetUrl - URL endpoint for repair execution
   * @param {Object} options - Execution options {operationType, correlationId}
   * @returns {Promise<Object>} Execution result
   */
  async executeRepairAction(action, targetUrl, options = {}) {
    const correlationId = options.correlationId || `repair-${Date.now()}`;
    
    try {
      logger.info('[REPAIR_SERVICE] Executing repair action', {
        correlationId,
        action: action.action,
        targetUrl,
        operationType: options.operationType || 'default'
      });

      const response = await this.httpClient.request('POST', targetUrl, {
        operationType: options.operationType || 'complex',
        correlationId,
        headers: {
          'Content-Type': 'application/json',
          'X-Correlation-ID': correlationId,
          'X-Repair-Action': action.action
        },
        body: JSON.stringify({
          action: action.action,
          parameters: action.parameters,
          strategy: action.strategy,
          correlationId
        })
      });

      logger.info('[REPAIR_SERVICE] Repair action executed successfully', {
        correlationId,
        status: response.status,
        action: action.action
      });

      return {
        status: 'SUCCESS',
        correlationId,
        httpStatus: response.status,
        response: response.body
      };
    } catch (error) {
      logger.error('[REPAIR_SERVICE] Repair action failed', {
        correlationId,
        action: action.action,
        error: error.message
      });

      return {
        status: 'FAILED',
        correlationId,
        error: error.message,
        actionTaken: action.action
      };
    }
  }

  /**
   * Get HTTP client health/circuit breaker status
   * @returns {Object} Circuit breaker state and statistics
   */
  getHealthStatus() {
    return {
      service: 'pipeline-repair',
      httpClient: {
        circuitBreaker: this.httpClient.getCircuitBreakerState(),
        configured: {
          maxAttempts: this.httpClient.maxAttempts,
          baseDelayMs: this.httpClient.baseDelayMs,
          timeouts: {
            basic: this.httpClient.basicTimeoutMs,
            complex: this.httpClient.complexTimeoutMs,
            default: this.httpClient.defaultTimeoutMs
          }
        }
      },
      strategies: this.strategies.map(s => ({ name: s.name, enabled: true }))
    };
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
