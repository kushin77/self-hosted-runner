const http = require('http');
const https = require('https');
const winston = require('winston');
const url = require('url');

const logger = winston.createLogger({
  level: 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json()
  ),
  transports: [new winston.transports.Console()]
});

/**
 * Circuit Breaker Pattern Implementation
 * Tracks failures and opens circuit after threshold exceeded
 */
class CircuitBreaker {
  constructor(options = {}) {
    this.failureThreshold = options.failureThreshold || 5;
    this.resetTimeoutMs = options.resetTimeoutMs || 60000; // 60s default
    this.state = 'CLOSED'; // CLOSED, OPEN, HALF_OPEN
    this.failureCount = 0;
    this.lastFailureTime = null;
    this.successSinceOpen = 0;
  }

  recordSuccess() {
    this.failureCount = 0;
    if (this.state === 'HALF_OPEN') {
      this.state = 'CLOSED';
      this.successSinceOpen = 0;
      logger.info('[CIRCUIT_BREAKER] Circuit reset to CLOSED after successful attempt');
    }
  }

  recordFailure() {
    this.failureCount++;
    this.lastFailureTime = Date.now();
    
    if (this.failureCount >= this.failureThreshold) {
      this.state = 'OPEN';
      logger.warn('[CIRCUIT_BREAKER] Circuit OPENED after threshold', {
        failureCount: this.failureCount,
        threshold: this.failureThreshold
      });
    }
  }

  isOpen() {
    if (this.state === 'OPEN') {
      const timeSinceFailure = Date.now() - this.lastFailureTime;
      if (timeSinceFailure > this.resetTimeoutMs) {
        this.state = 'HALF_OPEN';
        this.failureCount = 0;
        logger.info('[CIRCUIT_BREAKER] Circuit transitioned to HALF_OPEN (attempting recovery)');
      }
    }
    return this.state === 'OPEN';
  }

  getState() {
    return this.state;
  }
}

/**
 * Resilient HTTP Client with exponential backoff, timeout management, and circuit breaker
 */
class ResilientHttpClient {
  constructor(options = {}) {
    // Retry configuration
    this.maxAttempts = options.maxAttempts || 5;
    this.baseDelayMs = options.baseDelayMs || 2000; // base 2s
    this.maxDelayMs = options.maxDelayMs || 30000; // cap 30s
    this.jitter = options.jitter !== false; // enable by default

    // Timeout configuration
    this.basicTimeoutMs = options.basicTimeoutMs || 10000; // 10s for basic ops
    this.complexTimeoutMs = options.complexTimeoutMs || 30000; // 30s for complex ops
    this.defaultTimeoutMs = options.defaultTimeoutMs || 15000; // 15s default

    // Circuit breaker
    this.circuitBreaker = new CircuitBreaker(options.circuitBreaker || {});

    // Transient error patterns
    this.transientErrors = [
      /timeout/i, /ECONNREFUSED/i, /ECONNRESET/i, /socket hangup/i,
      /503 Service Unavailable/i, /429 Too Many Requests/i, /ETIMEDOUT/i,
      /read.*timeout/i, /write.*timeout/i
    ];

    logger.info('[HTTP_CLIENT] Initialized resilient HTTP client', {
      maxAttempts: this.maxAttempts,
      baseDelayMs: this.baseDelayMs,
      timeouts: {
        basic: this.basicTimeoutMs,
        complex: this.complexTimeoutMs,
        default: this.defaultTimeoutMs
      }
    });
  }

  /**
   * Determine timeout based on operation type
   * @param {string} operationType - 'basic', 'complex', or undefined (default)
   * @returns {number} Timeout in milliseconds
   */
  getTimeout(operationType) {
    switch (operationType) {
      case 'basic': return this.basicTimeoutMs;
      case 'complex': return this.complexTimeoutMs;
      default: return this.defaultTimeoutMs;
    }
  }

  /**
   * Calculate exponential backoff with optional jitter
   * @param {number} attempt - Attempt number (1-based)
   * @returns {number} Delay in milliseconds
   */
  calculateBackoff(attempt) {
    let delay = Math.min(
      this.baseDelayMs * Math.pow(2, attempt - 1),
      this.maxDelayMs
    );

    // Apply jitter (+/- 25%) if enabled
    if (this.jitter) {
      const jitterRange = Math.floor(delay * 0.25);
      const jitter = Math.floor(Math.random() * (jitterRange * 2 + 1)) - jitterRange;
      delay = Math.max(0, delay + jitter);
    }

    return delay;
  }

  /**
   * Check if an error is transient and should trigger retry
   * @param {Error} error - Error object or error message
   * @param {number} statusCode - HTTP status code if applicable
   * @returns {boolean} True if error is transient
   */
  isTransientError(error, statusCode) {
    const errorMsg = error.message || error.toString() || '';
    
    // Transient HTTP status codes
    const transientStatusCodes = [408, 429, 500, 502, 503, 504];
    if (statusCode && transientStatusCodes.includes(statusCode)) {
      return true;
    }

    // Check error message patterns
    return this.transientErrors.some(regex => regex.test(errorMsg));
  }

  /**
   * Make HTTP request with retry, timeout, and circuit breaker support
   * @param {string} method - HTTP method (GET, POST, etc.)
   * @param {string} targetUrl - Full URL to request
   * @param {Object} options - Request options
   * @param {string} options.operationType - 'basic' or 'complex' (determines timeout)
   * @param {string} options.body - Request body for POST/PUT
   * @param {Object} options.headers - Additional headers
   * @param {string} options.correlationId - Correlation ID for logging
   * @returns {Promise<Object>} Response object {status, headers, body}
   */
  async request(method, targetUrl, options = {}) {
    const correlationId = options.correlationId || `req-${Date.now()}...`;
    const operationType = options.operationType || 'default';
    const timeout = this.getTimeout(operationType);

    let lastError;

    for (let attempt = 1; attempt <= this.maxAttempts; attempt++) {
      // Check circuit breaker
      if (this.circuitBreaker.isOpen()) {
        logger.error('[HTTP_CLIENT] Circuit breaker is OPEN; rejecting request', {
          correlationId,
          attempt,
          url: targetUrl
        });
        throw new Error(`Circuit breaker OPEN - service temporarily unavailable (${this.circuitBreaker.getState()})`);
      }

      try {
        logger.info('[HTTP_CLIENT] Starting request', {
          correlationId,
          method,
          url: targetUrl,
          attempt,
          timeout: timeout,
          maxAttempts: this.maxAttempts
        });

        const response = await this._makeRequest(method, targetUrl, timeout, options);
        
        // Success - record in circuit breaker
        this.circuitBreaker.recordSuccess();
        
        logger.info('[HTTP_CLIENT] Request succeeded', {
          correlationId,
          attempt,
          status: response.status
        });

        return response;
      } catch (error) {
        lastError = error;
        const isTransient = this.isTransientError(error, error.statusCode);

        logger.warn('[HTTP_CLIENT] Request failed', {
          correlationId,
          attempt,
          method,
          url: targetUrl,
          error: error.message,
          isTransient,
          statusCode: error.statusCode
        });

        // Record failure in circuit breaker
        this.circuitBreaker.recordFailure();

        // Don't retry if error is not transient or we've exhausted attempts
        if (!isTransient || attempt >= this.maxAttempts) {
          logger.error('[HTTP_CLIENT] Request failed permanently', {
            correlationId,
            attempt,
            error: error.message,
            reason: !isTransient ? 'non-transient error' : 'max attempts reached'
          });

          // Emit metric for circuit breaker monitoring
          this._emitMetric({
            name: 'http_client_failures_exhausted',
            value: 1,
            tags: { url: targetUrl, operationType }
          });

          throw error;
        }

        // Calculate backoff and retry
        const backoffMs = this.calculateBackoff(attempt);
        logger.info('[HTTP_CLIENT] Scheduling retry', {
          correlationId,
          attempt,
          nextAttempt: attempt + 1,
          backoffMs,
          circuitBreakerState: this.circuitBreaker.getState()
        });

        // Emit retry metric
        this._emitMetric({
          name: 'http_client_retries',
          value: 1,
          tags: { url: targetUrl, attempt, operationType }
        });

        // Wait before retrying
        await this._sleep(backoffMs);
      }
    }

    // All attempts exhausted
    throw lastError;
  }

  /**
   * Internal: Make a single HTTP request with timeout
   */
  _makeRequest(method, targetUrl, timeoutMs, options = {}) {
    return new Promise((resolve, reject) => {
      try {
        const parsedUrl = new url.URL(targetUrl);
        const protocol = parsedUrl.protocol === 'https:' ? https : http;

        const requestOptions = {
          method,
          timeout: timeoutMs,
          headers: {
            'User-Agent': 'ResilientHttpClient/1.0',
            ...options.headers
          }
        };

        const req = protocol.request(parsedUrl, requestOptions, (res) => {
          let data = '';

          res.on('data', chunk => {
            data += chunk;
          });

          res.on('end', () => {
            resolve({
              status: res.statusCode,
              headers: res.headers,
              body: data
            });
          });
        });

        req.on('error', (error) => {
          reject(error);
        });

        req.on('timeout', () => {
          req.destroy();
          const err = new Error(`Request timeout after ${timeoutMs}ms`);
          err.code = 'ETIMEDOUT';
          reject(err);
        });

        if (options.body) {
          req.write(options.body);
        }

        req.end();
      } catch (error) {
        reject(error);
      }
    });
  }

  /**
   * Emit a metric event (for Prometheus/monitoring integration)
   */
  _emitMetric(metric) {
    // TODO: Integrate with Prometheus client
    logger.debug('[METRIC]', metric);
  }

  /**
   * Sleep helper for backoff delays
   */
  _sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  /**
   * Get circuit breaker state (for monitoring/debugging)
   */
  getCircuitBreakerState() {
    return {
      state: this.circuitBreaker.getState(),
      failureCount: this.circuitBreaker.failureCount,
      threshold: this.circuitBreaker.failureThreshold
    };
  }
}

module.exports = ResilientHttpClient;
