"use strict";

const fs = require('fs');
const path = require('path');

// Simple in-memory job store for provisioner-worker used in local runs.
const store = new Map();
// Secondary index mapping planHash -> request_id for idempotency across requests
const planIndex = new Map();

const JOBSTORE_FILE = process.env.JOBSTORE_FILE || path.join('services', 'provisioner-worker', 'data', 'jobstore.json');
const JOBSTORE_PERSIST = (process.env.JOBSTORE_PERSIST || '1') === '1';

function loadFromDisk() {
  try {
    if (!JOBSTORE_PERSIST) return;
    if (!fs.existsSync(JOBSTORE_FILE)) return;
    const raw = fs.readFileSync(JOBSTORE_FILE, 'utf8');
    const obj = JSON.parse(raw || '{}');
    if (obj && obj.store) {
      Object.entries(obj.store).forEach(([k, v]) => store.set(String(k), v));
    }
    if (obj && obj.planIndex) {
      Object.entries(obj.planIndex).forEach(([k, v]) => planIndex.set(String(k), String(v)));
    }
  } catch (e) {
    // ignore load errors but do not crash the worker
  }
}

function saveToDisk() {
  try {
    if (!JOBSTORE_PERSIST) return;
    const dir = path.dirname(JOBSTORE_FILE);
    fs.mkdirSync(dir, { recursive: true });
    const payload = { store: Object.fromEntries(store), planIndex: Object.fromEntries(planIndex) };
    const tmp = JOBSTORE_FILE + '.tmp';
    fs.writeFileSync(tmp, JSON.stringify(payload, null, 2), 'utf8');
    fs.renameSync(tmp, JOBSTORE_FILE);
  } catch (e) {
    // swallow persistence errors to avoid stopping the worker
  }
}

loadFromDisk();

function get(id) {
  if (!id) return null;
  return store.get(String(id)) || null;
}

function set(idOrObj, obj) {
  let result = null;
  if (typeof idOrObj === 'object' && idOrObj !== null && idOrObj.request_id) {
    const id = String(idOrObj.request_id);
    store.set(id, idOrObj);
    if (idOrObj.planHash) planIndex.set(idOrObj.planHash, id);
    result = idOrObj;
  } else if (typeof idOrObj === 'string' && obj) {
    const id = String(idOrObj);
    store.set(id, obj);
    if (obj && obj.planHash) planIndex.set(obj.planHash, id);
    result = obj;
  }
  // persist asynchronously (best-effort)
  try { saveToDisk(); } catch (e) {}
  return result;
}

function setPlanHash(planHash, requestId) {
  if (!planHash || !requestId) return false;
  planIndex.set(String(planHash), String(requestId));
  const rec = store.get(String(requestId)) || null;
  if (rec) {
    rec.planHash = String(planHash);
    store.set(String(requestId), rec);
  }
  try { saveToDisk(); } catch (e) {}
  return true;
}

function getByPlanHash(planHash) {
  if (!planHash) return null;
  const id = planIndex.get(String(planHash));
  if (!id) return null;
  return store.get(String(id)) || null;
}

function list() {
  return Array.from(store.values());
}

module.exports = { get, set, list, setPlanHash, getByPlanHash };
