/**
 * ApprovalEngine - Gating mechanism for medium/high-risk repairs
 * Enforces approval workflows for significant operational changes
 */
const approvals = require('./approvals');
class ApprovalEngine {
  constructor(options = {}) {
    this.approvalThreshold = options.threshold || 0.7;
    this.riskLevels = {
      LOW: 0.1,
      MEDIUM: 0.5,
      HIGH: 0.9
    };
    this.pendingApprovals = new Map(); // eventId -> approval request
    this.approvalCallbacks = []; // registered approval handlers
  }

  /**
   * Determine if action requires approval based on risk and confidence
   */
  requiresApproval(action, confidence) {
    const riskScore = this.riskLevels[action.risk] || 0.5;
    const overallRisk = riskScore * (1 - confidence); // risk adjusted by confidence
    return overallRisk > (1 - this.approvalThreshold);
  }

  /**
   * Request approval for autonomous repair
   */
  async requestApproval(eventId, event, action, reason) {
    const request = {
      id: `apr-${eventId}-${Date.now()}`,
      eventId,
      action,
      reason,
      event: {
        id: event.id,
        errorMessage: event.errorMessage
      },
      status: 'PENDING',
      requestedAt: new Date().toISOString(),
      expiresAt: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
      approvals: [],
      rejections: []
    };

    this.pendingApprovals.set(eventId, request);
    
    // Notify registered handlers
    for (const callback of this.approvalCallbacks) {
      try {
        await callback(request);
      } catch (err) {
        console.error(`Approval callback failed: ${err.message}`);
      }
    }

    // persist and notify Slack (handled by approvals.requestApproval)
    try {
      await approvals.requestApproval(eventId, request);
    } catch (err) {
      console.error('persisting approval request failed:', err && err.message);
    }

    return request;
  }

  /**
   * Approve a pending repair
   */
  async approveRepair(eventId, approver, reason = '') {
    const request = this.pendingApprovals.get(eventId);
    if (!request) {
      throw new Error(`No pending approval for event ${eventId}`);
    }

    request.approvals.push({
      approver,
      reason,
      approvedAt: new Date().toISOString()
    });

    request.status = 'APPROVED';
    // persist final state
    try {
      approvals.addApproval(eventId, request);
    } catch (err) {
      console.error('persisting approval decision failed:', err && err.message);
    }
    return {
      decision: 'APPROVED',
      approver,
      reason,
      timestamp: new Date().toISOString(),
      riskLevel: request.action.risk
    };
  }

  /**
   * Reject a pending repair
   */
  async rejectRepair(eventId, rejector, reason = '') {
    const request = this.pendingApprovals.get(eventId);
    if (!request) {
      throw new Error(`No pending approval for event ${eventId}`);
    }

    request.rejections.push({
      rejector,
      reason,
      rejectedAt: new Date().toISOString()
    });

    request.status = 'REJECTED';
    try {
      approvals.addApproval(eventId, request);
    } catch (err) {
      console.error('persisting rejection failed:', err && err.message);
    }
    return {
      decision: 'REJECTED',
      rejector,
      reason,
      timestamp: new Date().toISOString()
    };
  }

  /**
   * Check if repair has been approved
   */
  isApproved(eventId) {
    const request = this.pendingApprovals.get(eventId);
    return request?.status === 'APPROVED';
  }

  /**
   * Get approval status for event
   */
  getApprovalStatus(eventId) {
    const request = this.pendingApprovals.get(eventId);
    if (!request) {
      return { status: 'NOT_FOUND', eventId };
    }

    return {
      eventId,
      status: request.status,
      approvals: request.approvals.length,
      rejections: request.rejections.length,
      expiresAt: request.expiresAt,
      action: request.action
    };
  }

  /**
   * Register a callback for approval requests
   * Useful for integrating with Slack, PagerDuty, etc.
   */
  onApprovalRequest(callback) {
    this.approvalCallbacks.push(callback);
  }

  /**
   * Cleanup expired approval requests
   */
  cleanup() {
    const now = new Date();
    for (const [eventId, request] of this.pendingApprovals.entries()) {
      if (new Date(request.expiresAt) < now) {
        this.pendingApprovals.delete(eventId);
      }
    }
  }
}

module.exports = ApprovalEngine;
