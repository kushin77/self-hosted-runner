const fs = require('fs');
const path = require('path');
const winston = require('winston');

/**
 * AuditLog - Immutable audit trail for repairs
 * Logs all repair decisions for compliance and debugging
 */
class AuditLog {
  constructor(options = {}) {
    this.logDir = options.logDir || './repairs/audit';
    this.filename = options.filename || 'repairs.log';
    this.retention = options.retention || 90; // days
    
    // Ensure log directory exists
    if (!fs.existsSync(this.logDir)) {
      fs.mkdirSync(this.logDir, { recursive: true });
    }

    // Setup logger with file transport
    this.logger = winston.createLogger({
      level: 'info',
      format: winston.format.combine(
        winston.format.timestamp({ format: 'YYYY-MM-DD HH:mm:ss' }),
        winston.format.json()
      ),
      defaultMeta: { service: 'pipeline-repair-audit' },
      transports: [
        new winston.transports.File({
          filename: path.join(this.logDir, this.filename),
          maxsize: 10485760, // 10MB
          maxFiles: 10
        })
      ]
    });
  }

  /**
   * Log an analysis event
   */
  logAnalysis(eventId, failureEvent, analysisResult) {
    this.logger.info('ANALYSIS_COMPLETE', {
      eventId,
      errorMessage: failureEvent.errorMessage,
      strategy: analysisResult.recommendation?.strategy,
      confidence: analysisResult.confidence,
      requiresApproval: analysisResult.requiresApproval,
      status: analysisResult.status
    });
  }

  /**
   * Log an approval decision
   */
  logApproval(eventId, approvalResult) {
    this.logger.info('APPROVAL_DECISION', {
      eventId,
      decision: approvalResult.decision,
      approver: approvalResult.approver,
      reason: approvalResult.reason,
      timestamp: approvalResult.timestamp,
      riskLevel: approvalResult.riskLevel
    });
  }

  /**
   * Log action execution
   */
  logExecution(eventId, action, result) {
    this.logger.info('ACTION_EXECUTED', {
      eventId,
      action: action.action,
      strategy: action.strategy,
      result: result.status,
      error: result.error || null,
      executedAt: new Date().toISOString()
    });
  }

  /**
   * Get audit trail for event
   */
  getAuditTrail(eventId) {
    // This would typically read from DB/file
    // For MVP, return a placeholder that could be queried
    return {
      eventId,
      entries: [],
      note: 'Full audit trail retrieval requires persistent store'
    };
  }

  /**
   * Cleanup old logs based on retention policy
   */
  cleanup() {
    const now = Date.now();
    const retentionMs = this.retention * 24 * 60 * 60 * 1000;
    
    try {
      const files = fs.readdirSync(this.logDir);
      files.forEach(file => {
        const filepath = path.join(this.logDir, file);
        const stat = fs.statSync(filepath);
        if (now - stat.mtime.getTime() > retentionMs) {
          fs.unlinkSync(filepath);
        }
      });
    } catch (err) {
      this.logger.error('CLEANUP_FAILED', { error: err.message });
    }
  }
}

module.exports = AuditLog;
