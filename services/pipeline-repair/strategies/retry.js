const RepairStrategy = require('./base');

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
    return isTransient ? 0.8 : 0;
  }

  async execute(event) {
    const attempt = event.attemptNumber || 1;
    const delay = Math.pow(2, attempt) * 1000;
    return {
      action: 'RETRY',
      strategy: this.name,
      parameters: { delayMs: delay, attempt: attempt + 1 },
      risk: 'LOW'
    };
  }
}

module.exports = RetryStrategy;
