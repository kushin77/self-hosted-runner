const RepairStrategy = require('./base');

/**
 * Retry Repair Strategy
 * Detects transient/network/environment failures and recommends retry with backoff.
 */
class RetryStrategy extends RepairStrategy {
  constructor() {
    super('retry-strategy');
    this.transientErrors = [
      /timeout/i, /connection reset/i, /socket hangup/i, 
      /EAI_AGAIN/i, /ECONNREFUSED/i, /503 Service Unavailable/i,
      /resource temporarily unavailable/i
    ];
  }

  assess(event) {
    const errorMsg = event.errorMessage || event.logExcerpt || '';
    const isTransient = this.transientErrors.some(regex => regex.test(errorMsg));
    
    // Confidence is 0.8 if transient pattern detected
    return isTransient ? 0.8 : 0;
  }

  async execute(event) {
    // In MVP, we just recommend a retry with a calculated backoff
    const attempt = event.attemptNumber || 1;
    const delay = Math.pow(2, attempt) * 1000; // Exponential backoff
    
    return {
      action: 'RETRY',
      strategy: this.name,
      parameters: { delayMs: delay, attempt: attempt + 1 },
      risk: 'LOW'
    };
  }
}

module.exports = RetryStrategy;
