const fs = require('fs');
const path = require('path');

const STORE_FILE = process.env.PROVISIONER_JOB_STORE || path.join(__dirname, '..', '.provisioner', 'jobs.json');

function ensureDir(p) {
  const dir = path.dirname(p);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
}

function load() {
  try {
    if (!fs.existsSync(STORE_FILE)) return {};
    return JSON.parse(fs.readFileSync(STORE_FILE, 'utf8') || '{}');
  } catch (e) {
    return {};
  }
}

function save(store) {
  ensureDir(STORE_FILE);
  fs.writeFileSync(STORE_FILE, JSON.stringify(store, null, 2), 'utf8');
}

function get(jobId) {
  const store = load();
  return store[jobId] || null;
}

function set(jobId, data) {
  const store = load();
  store[jobId] = data;
  save(store);
}

module.exports = { get, set };
