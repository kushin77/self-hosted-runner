// Approvals store with simple JSON persistence and optional Slack notifications
const fs = require('fs');
const path = require('path');
const axios = require('axios');

const DATA_DIR = process.env.REPAIR_DATA_DIR || path.join(__dirname, '..', '..', 'data');
const APPROVALS_FILE = path.join(DATA_DIR, 'approvals.json');

// In-memory cache
const approvals = new Map();

function ensureDataDir() {
  try {
    fs.mkdirSync(DATA_DIR, { recursive: true });
  } catch (err) {
    // ignore
  }
}

function persist() {
  ensureDataDir();
  const obj = {};
  for (const [k, v] of approvals.entries()) obj[k] = v;
  fs.writeFileSync(APPROVALS_FILE, JSON.stringify(obj, null, 2), { mode: 0o600 });
}

function load() {
  try {
    const raw = fs.readFileSync(APPROVALS_FILE, 'utf8');
    const obj = JSON.parse(raw || '{}');
    for (const k of Object.keys(obj)) approvals.set(k, obj[k]);
  } catch (err) {
    // ignore missing file
  }
}

async function notifySlack(eventId, approvalRequest) {
  const webhook = process.env.APPROVAL_SLACK_WEBHOOK || '';
  if (!webhook) return;
  try {
    await axios.post(webhook, {
      text: `Approval requested for event ${eventId}: ${approvalRequest.reason || ''}`,
      attachments: [ { text: JSON.stringify(approvalRequest, null, 2) } ]
    }, { timeout: 5000 });
  } catch (err) {
    // log but don't fail
    console.error('Slack notify failed:', err.message);
  }
}

function addApproval(eventId, record) {
  approvals.set(eventId, record);
  persist();
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

async function requestApproval(eventId, approvalRequest) {
  approvals.set(eventId, { request: approvalRequest, status: 'REQUESTED' });
  persist();
  await notifySlack(eventId, approvalRequest);
}

load();

module.exports = { addApproval, hasApproval, getApproval, list, requestApproval };
