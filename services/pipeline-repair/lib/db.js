const path = require('path');
const fs = require('fs');
const sqlite3 = require('sqlite3');

const DATA_DIR = path.resolve(__dirname, '..', 'data');
const DB_PATH = path.join(DATA_DIR, 'repair.db');

function ensureDataDir() {
  try {
    fs.mkdirSync(DATA_DIR, { recursive: true });
  } catch (e) {
    // ignore
  }
}

function openDb() {
  ensureDataDir();
  return new sqlite3.Database(DB_PATH);
}

function run(db, sql, params=[]) {
  return new Promise((res, rej) => db.run(sql, params, function(err) {
    if (err) return rej(err);
    res(this);
  }));
}

function all(db, sql, params=[]) {
  return new Promise((res, rej) => db.all(sql, params, (err, rows) => {
    if (err) return rej(err);
    res(rows);
  }));
}

async function init() {
  const db = openDb();
  await run(db, `PRAGMA journal_mode = WAL;`);
  await run(db, `CREATE TABLE IF NOT EXISTS proposals (
    id TEXT PRIMARY KEY,
    eventId TEXT,
    createdAt TEXT,
    confidence REAL,
    risk TEXT,
    requiresApproval INTEGER,
    recommendedAction TEXT,
    strategy TEXT,
    parameters TEXT,
    rawRecommendation TEXT,
    sourceEvent TEXT
  );`);

  await run(db, `CREATE TABLE IF NOT EXISTS executions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    eventId TEXT,
    executedAt TEXT,
    result TEXT
  );`);

  db.close();
}

async function saveProposal(p) {
  const db = openDb();
  const sql = `INSERT OR REPLACE INTO proposals (id,eventId,createdAt,confidence,risk,requiresApproval,recommendedAction,strategy,parameters,rawRecommendation,sourceEvent)
    VALUES (?,?,?,?,?,?,?,?,?,?,?)`;
  const params = [
    p.proposalId,
    p.eventId,
    p.createdAt,
    p.confidence || null,
    p.risk || null,
    p.requiresApproval ? 1 : 0,
    p.recommendedAction || null,
    p.strategy || null,
    JSON.stringify(p.parameters || {}),
    JSON.stringify(p.rawRecommendation || {}),
    JSON.stringify(p.sourceEvent || {})
  ];
  await run(db, sql, params);
  db.close();
}

async function listProposals() {
  const db = openDb();
  const rows = await all(db, `SELECT * FROM proposals ORDER BY createdAt DESC`);
  db.close();
  return rows.map(r => ({
    proposalId: r.id,
    eventId: r.eventId,
    createdAt: r.createdAt,
    confidence: r.confidence,
    risk: r.risk,
    requiresApproval: !!r.requiresApproval,
    recommendedAction: r.recommendedAction,
    strategy: r.strategy,
    parameters: JSON.parse(r.parameters || '{}'),
    rawRecommendation: JSON.parse(r.rawRecommendation || '{}'),
    sourceEvent: JSON.parse(r.sourceEvent || '{}')
  }));
}

async function recordExecution(eventId, executedAt, result) {
  const db = openDb();
  await run(db, `INSERT INTO executions (eventId, executedAt, result) VALUES (?,?,?)`, [eventId, executedAt, JSON.stringify(result || {})]);
  db.close();
}

module.exports = {
  init,
  saveProposal,
  listProposals,
  recordExecution
};
