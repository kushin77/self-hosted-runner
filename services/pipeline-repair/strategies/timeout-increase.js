const RepairStrategy = require('./base');

/**
 * TimeoutIncreaseStrategy - Safe timeout adjustment repair primitive
 * Detects timeout-related failures and recommends safe timeout increases
 */
class TimeoutIncreaseStrategy extends RepairStrategy {
  constructor() {
    super('timeout-increase-strategy');
    this.timeoutPatterns = [
      /timeout/i, /timed out/i, /deadline exceeded/i,
      /operation.*timeout/i, /read.*timeout/i, /write.*timeout/i,
      /request.*timeout/i, /socket.*timeout/i
    ];
    this.maxMultiplier = 4; // max 4x original timeout
  }

  assess(event) {
    const errorMsg = event.errorMessage || event.logExcerpt || '';
    const isTimeout = this.timeoutPatterns.some(regex => regex.test(errorMsg));
    
    if (!isTimeout) return 0;

    // Extract current timeout if available
    const timeoutMatch = errorMsg.match(/(\d+)\s*(ms|s|sec|seconds|milliseconds)/i);
    const hasTimeoutValue = !!timeoutMatch;
    
    // Increase confidence if we can extract current timeout value
    return hasTimeoutValue ? 0.75 : 0.65;
  }

  async execute(event) {
    // Extract current timeout from error message if possible
    const errorMsg = event.errorMessage || event.logExcerpt || '';
    const timeoutMatch = errorMsg.match(/(\d+)\s*(ms|s|sec|seconds|milliseconds)/i);
    
    let currentTimeoutMs = 30000; // default 30s
    if (timeoutMatch) {
      const value = parseInt(timeoutMatch[1], 10);
      const unit = timeoutMatch[2].toLowerCase();
      currentTimeoutMs = unit.includes('s') && !unit.includes('ms') ? value * 1000 : value;
    }

    // Recommend 2x increase (safe default)
    const newTimeoutMs = Math.min(currentTimeoutMs * 2, currentTimeoutMs * this.maxMultiplier);
    
    return {
      action: 'INCREASE_TIMEOUT',
      strategy: this.name,
      parameters: {
        currentTimeoutMs,
        newTimeoutMs,
        multiplier: newTimeoutMs / currentTimeoutMs
      },
      risk: 'MEDIUM', // Medium risk - changes timing semantics
      rationale: 'Timeout exceeded; recommend safe increase to allow operation completion'
    };
  }
}

module.exports = TimeoutIncreaseStrategy;
