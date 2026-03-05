// Simple in-memory approvals store for MVP
const approvals = new Map();

function addApproval(eventId, record) {
  approvals.set(eventId, record);
}

function hasApproval(eventId) {
  return approvals.has(eventId);
}

function getApproval(eventId) {
  return approvals.get(eventId) || null;
}

function list() {
  const out = [];
  for (const [id, rec] of approvals.entries()) out.push({ eventId: id, ...rec });
  return out;
}

module.exports = { addApproval, hasApproval, getApproval, list };
