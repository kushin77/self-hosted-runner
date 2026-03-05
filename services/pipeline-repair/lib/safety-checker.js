/**
 * AI Agent Safety Checker
 * Implements safety guarantees from docs/AI_AGENT_SAFETY_FRAMEWORK.md:
 * 1. Reversibility: All autonomous actions must be reversible
 * 2. Bounded Scope: Actions must have clearly bounded scope
 * 3. Safety Limits: Cost bounds, resource limits, time bounds
 */
const axios = require('axios');

class SafetyChecker {
  constructor(options = {}) {
    this.auditLog = [];
    this.config = {
      maxCostIncreasePercent: options.maxCostIncreasePercent || 10, // max 10% increase
      maxTimeoutSeconds: options.maxTimeoutSeconds || 300, // 5min max
      maxScalingPercent: options.maxScalingPercent || 20, // max 20% scale
      maxMemoryIncreaseMB: options.maxMemoryIncreaseMB || 512, // 512MB max
      slackWebhook: options.slackWebhook || process.env.SAFETY_SLACK_WEBHOOK,
      pagerDutyKey: options.pagerDutyKey || process.env.PAGERDUTY_KEY,
    };
  }

  /**
   * Safety categories per AI_AGENT_SAFETY_FRAMEWORK
   */
  getSafetyCategory(action) {
    // 🟢 Green (Auto-Executable)
    if (['log_format', 'metric_collection', 'cache_invalidation', 'config_read', 'status_check'].includes(action.type)) {
      return 'GREEN';
    }

    // 🟡 Yellow (Requires Approval)
    if (['increase_timeout', 'enable_optimization', 'scale_up', 'canary_deploy', 'enable_feature_flag'].includes(action.type)) {
      return 'YELLOW';
    }

    // 🔴 Red (Forbidden)
    if (['delete_data', 'disable_security', 'disable_audit', 'reduce_limits', 'force_terminate', 'modify_auth'].includes(action.type)) {
      return 'RED';
    }

    return 'UNKNOWN';
  }

  /**
   * Check if action is reversible
   */
  isReversible(action) {
    const nonReversible = [
      'delete_data',
      'delete_logs',
      'force_terminate',
      'disable_audit',
      'disable_security',
    ];

    if (nonReversible.includes(action.type)) {
      return { reversible: false, reason: `Action type '${action.type}' is inherently non-reversible` };
    }

    // Check for destructive patterns in the action
    if (action.description && action.description.toLowerCase().includes('permanently delete')) {
      return { reversible: false, reason: 'Action description indicates permanent deletion' };
    }

    return { reversible: true, reason: `Action '${action.type}' can be reversed` };
  }

  /**
   * Check if scope is bounded
   */
  validateScope(action) {
    const errors = [];

    // Check for meaningful scope limits
    if (!action.scope) {
      errors.push('Action must have defined scope (e.g., specific pipeline, runner pool)');
    } else if (action.scope === 'global' || action.scope === '*' || action.scope === 'all') {
      errors.push(`Scope too broad: '${action.scope}'. Must target specific resource(s).`);
    }

    // For scaling actions, verify max bounds
    if (action.type === 'scale_up' || action.type === 'scale_runner_pool') {
      if (!action.maxInstances || action.maxInstances > 100) {
        errors.push(`Scaling action missing or excessive maxInstances limit (${action.maxInstances || 'none'})`);
      }
      if (!action.currentInstances) {
        errors.push('Scaling action must specify currentInstances for validation');
      }
    }

    return {
      bounded: errors.length === 0,
      errors,
    };
  }

  /**
   * Check cost bounds for resource changes
   */
  validateCostBounds(action, baseline = {}) {
    const errors = [];

    if (action.type === 'increase_memory') {
      const increase = action.newSizeMB - (action.currentSizeMB || 0);
      if (increase > this.config.maxMemoryIncreaseMB) {
        errors.push(`Memory increase too large: +${increase}MB (max: ${this.config.maxMemoryIncreaseMB}MB)`);
      }
    }

    if (action.type === 'scale_up') {
      const percentIncrease = ((action.targetCount - action.currentCount) / action.currentCount) * 100;
      if (percentIncrease > this.config.maxScalingPercent) {
        errors.push(`Scaling increase too large: +${percentIncrease.toFixed(1)}% (max: ${this.config.maxScalingPercent}%)`);
      }
    }

    if (action.estimatedCostDelta) {
      const percentIncrease = (action.estimatedCostDelta / (baseline.currentMonthlyCost || 100)) * 100;
      if (percentIncrease > this.config.maxCostIncreasePercent) {
        errors.push(`Cost increase too large: +${percentIncrease.toFixed(1)}% (max: ${this.config.maxCostIncreasePercent}%)`);
      }
    }

    return {
      withinBounds: errors.length === 0,
      errors,
      estimatedCostDelta: action.estimatedCostDelta || 0,
    };
  }

  /**
   * Check time limits (action duration, timeout bounds)
   */
  validateTimeBounds(action) {
    const errors = [];

    if (action.type === 'increase_timeout') {
      if (action.newTimeoutSeconds > this.config.maxTimeoutSeconds) {
        errors.push(`Timeout too large: ${action.newTimeoutSeconds}s (max: ${this.config.maxTimeoutSeconds}s)`);
      }
    }

    // Check estimated duration
    if (action.estimatedDurationSeconds && action.estimatedDurationSeconds > 3600) {
      errors.push(`Action duration excessive: ${action.estimatedDurationSeconds}s (>1 hour)`);
    }

    return {
      timeBounded: errors.length === 0,
      errors,
    };
  }

  /**
   * Comprehensive safety check
   * Returns { safe, category, violations, recommendation }
   */
  async checkSafety(action, context = {}) {
    const result = {
      actionId: action.id || `action-${Date.now()}`,
      actionType: action.type,
      category: this.getSafetyCategory(action),
      timestamp: new Date().toISOString(),
      violations: [],
      checks: {},
    };

    // Check reversibility
    const reversibility = this.isReversible(action);
    result.checks.reversibility = reversibility;
    if (!reversibility.reversible) {
      result.violations.push(`NOT_REVERSIBLE: ${reversibility.reason}`);
    }

    // Check scope bounds
    const scopeCheck = this.validateScope(action);
    result.checks.scope = scopeCheck;
    if (!scopeCheck.bounded) {
      result.violations.push(...scopeCheck.errors);
    }

    // Check cost bounds
    const costCheck = this.validateCostBounds(action, context.baseline);
    result.checks.cost = costCheck;
    if (!costCheck.withinBounds) {
      result.violations.push(...costCheck.errors);
    }

    // Check time bounds
    const timeCheck = this.validateTimeBounds(action);
    result.checks.time = timeCheck;
    if (!timeCheck.timeBounded) {
      result.violations.push(...timeCheck.errors);
    }

    // Determine safety decision
    if (result.category === 'RED') {
      result.safe = false;
      result.recommendation = 'FORBIDDEN - this action cannot be executed autonomously';
    } else if (result.category === 'GREEN' && result.violations.length === 0) {
      result.safe = true;
      result.recommendation = 'AUTO_EXECUTABLE - no approval needed';
    } else if (result.category === 'YELLOW') {
      result.safe = result.violations.length === 0;
      result.recommendation = result.safe ? 'REQUIRES_APPROVAL' : 'BLOCKED_FOR_REVIEW';
    } else {
      result.safe = result.violations.length === 0;
      result.recommendation = 'UNKNOWN - manual review required';
    }

    // Audit and notify
    this.auditLog.push(result);
    if (!result.safe || result.category === 'RED') {
      await this.notifyOps(result, action, context);
    }

    return result;
  }

  /**
   * Notify ops/on-call of safety violations
   */
  async notifyOps(safetyResult, action, context = {}) {
    const message = {
      title: `⚠️ AI Safety Check: ${safetyResult.recommendation}`,
      action_type: safetyResult.actionType,
      violations: safetyResult.violations,
      category: safetyResult.category,
      timestamp: safetyResult.timestamp,
      context,
    };

    // Slack notification
    if (this.config.slackWebhook && safetyResult.category === 'RED') {
      try {
        await axios.post(this.config.slackWebhook, {
          text: `🔴 CRITICAL: Forbidden action attempted by AI agent`,
          attachments: [{
            color: 'danger',
            fields: [
              { title: 'Action Type', value: safetyResult.actionType, short: true },
              { title: 'Category', value: safetyResult.category, short: true },
              { title: 'Violations', value: safetyResult.violations.join('\n'), short: false },
              { title: 'Recommendation', value: safetyResult.recommendation, short: true },
            ],
          }],
        }, { timeout: 5000 });
      } catch (err) {
        console.error('Failed to notify Slack:', err.message);
      }
    }

    // PagerDuty escalation for critical violations
    if (this.config.pagerDutyKey && safetyResult.violations.length > 2) {
      try {
        await this.escalateToPagerDuty(message);
      } catch (err) {
        console.error('Failed to escalate to PagerDuty:', err.message);
      }
    }
  }

  /**
   * Escalate to PagerDuty for on-call team
   */
  async escalateToPagerDuty(message) {
    try {
      await axios.post('https://events.pagerduty.com/v2/enqueue', {
        routing_key: this.config.pagerDutyKey,
        event_action: 'trigger',
        payload: {
          summary: `AI Agent Safety Violation: ${message.title}`,
          severity: message.violations.length > 3 ? 'critical' : 'warning',
          source: 'ai-agent-safety-checker',
          custom_details: message,
        },
      }, { timeout: 5000 });
    } catch (err) {
      console.error('PagerDuty escalation failed:', err.message);
      throw err;
    }
  }

  /**
   * Get audit trail for AI actions
   */
  getAuditLog(filters = {}) {
    let logs = this.auditLog;

    if (filters.timeRange) {
      const minTime = new Date(filters.timeRange.start);
      const maxTime = new Date(filters.timeRange.end);
      logs = logs.filter(log => {
        const logTime = new Date(log.timestamp);
        return logTime >= minTime && logTime <= maxTime;
      });
    }

    if (filters.category) {
      logs = logs.filter(log => log.category === filters.category);
    }

    if (filters.actionType) {
      logs = logs.filter(log => log.actionType === filters.actionType);
    }

    return logs;
  }

  /**
   * Get safety metrics
   */
  getMetrics() {
    const total = this.auditLog.length;
    const safe = this.auditLog.filter(l => l.safe).length;
    const unsafe = this.auditLog.filter(l => !l.safe).length;
    const red = this.auditLog.filter(l => l.category === 'RED').length;
    const yellow = this.auditLog.filter(l => l.category === 'YELLOW').length;
    const green = this.auditLog.filter(l => l.category === 'GREEN').length;

    return {
      total,
      safe,
      unsafe,
      safetyRate: total > 0 ? (safe / total * 100).toFixed(2) + '%' : 'N/A',
      categoryDistribution: { RED: red, YELLOW: yellow, GREEN: green },
    };
  }
}

module.exports = SafetyChecker;
