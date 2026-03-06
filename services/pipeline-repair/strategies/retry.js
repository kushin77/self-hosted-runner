const RepairStrategy = require('./base');

/**
 * Retry Repair Strategy
 * Detects transient/network/environment failures and recommends retry with backoff.
 */
class RetryStrategy extends RepairStrategy {
  constructor(options = {}) {
    super('retry-strategy');
    this.transientErrors = [
      /timeout/i, /connection reset/i, /socket hangup/i, 
      /EAI_AGAIN/i, /ECONNREFUSED/i, /503 Service Unavailable/i,
      /resource temporarily unavailable/i
    ];

    // Options (tunable from RepairService)
    this.maxAttempts = typeof options.maxAttempts === 'number' ? options.maxAttempts : 5;
    this.baseDelayMs = typeof options.baseDelayMs === 'number' ? options.baseDelayMs : 1000; // base 1s
    this.maxDelayMs = typeof options.maxDelayMs === 'number' ? options.maxDelayMs : 60000; // cap 60s
    this.jitter = typeof options.jitter === 'boolean' ? options.jitter : true; // enable jitter
  }

  assess(event) {
    const errorMsg = event.errorMessage || event.logExcerpt || '';
    const isTransient = this.transientErrors.some(regex => regex.test(errorMsg));
    
    // Confidence is 0.8 if transient pattern detected
    return isTransient ? 0.8 : 0;
  }

  async execute(event) {
    // Calculate exponential backoff with jitter and cap, and enforce max attempts
    const attempt = Math.max(1, event.attemptNumber || 1);
    const nextAttempt = attempt + 1;

    // If we've already reached or exceeded max attempts, signal that manual intervention is needed
    if (attempt >= this.maxAttempts) {
      return {
        action: 'ESCALATE',
        strategy: this.name,
        parameters: { attempts: attempt, maxAttempts: this.maxAttempts },
        risk: 'HIGH',
        rationale: 'Max retry attempts reached; escalate for manual investigation'
      };
    }

    // Exponential backoff base calculation
    let delay = Math.min(this.baseDelayMs * Math.pow(2, attempt - 1), this.maxDelayMs);

    // Apply jitter (+/- 50%) if enabled
    if (this.jitter) {
      const jitterRange = Math.floor(delay * 0.5);
      const jitter = Math.floor(Math.random() * (jitterRange * 2 + 1)) - jitterRange; // -range..+range
      delay = Math.max(0, delay + jitter);
    }

    return {
      action: 'RETRY',
      strategy: this.name,
      parameters: { delayMs: delay, attempt: nextAttempt, maxAttempts: this.maxAttempts },
      risk: 'LOW',
      rationale: 'Transient error detected; recommend retry with backoff and jitter'
    };
  }
}

module.exports = RetryStrategy;
