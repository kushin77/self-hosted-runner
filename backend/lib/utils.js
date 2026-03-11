const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

// Shared in-memory audit trail used by backend entrypoints
const auditTrail = [];

function generateId() {
  return crypto.randomBytes(16).toString('hex').substring(0, 12);
}

function generateToken(userId) {
  const payload = {
    userId,
    iat: Math.floor(Date.now() / 1000),
    exp: Math.floor(Date.now() / 1000) + 86400
  };
  return Buffer.from(JSON.stringify(payload)).toString('base64');
}

function logAuditEntry(action, resource, status, userId, details) {
  const entry = {
    id: generateId(),
    timestamp: new Date().toISOString(),
    action,
    resource,
    status,
    userId: userId || 'system',
    details
  };
  auditTrail.push(entry);

  // Immutable JSONL append
  const logDir = path.join(process.cwd(), 'logs');
  try {
    if (!fs.existsSync(logDir)) {
      fs.mkdirSync(logDir, { recursive: true });
    }
    fs.appendFileSync(
      path.join(logDir, 'portal-api-audit.jsonl'),
      JSON.stringify(entry) + '\n'
    );
  } catch (e) {
    console.error('Audit log error:', e && e.message ? e.message : e);
  }
  return entry;
}

module.exports = {
  generateId,
  generateToken,
  logAuditEntry,
  auditTrail
};
