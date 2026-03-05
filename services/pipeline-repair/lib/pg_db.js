const { Pool } = require('pg');
const fs = require('fs');
const path = require('path');

const DEFAULT_CONN = process.env.REPAIR_PG_CONN || 'postgres://postgres:postgres@127.0.0.1:5432/repairdb';

let pool;

function getPool() {
  if (!pool) pool = new Pool({ connectionString: DEFAULT_CONN });
  return pool;
}

async function init() {
  const p = getPool();
  await p.query(`CREATE TABLE IF NOT EXISTS proposals (
    id TEXT PRIMARY KEY,
    eventId TEXT,
    createdAt TIMESTAMP WITH TIME ZONE,
    confidence REAL,
    risk TEXT,
    requiresApproval BOOLEAN,
    recommendedAction TEXT,
    strategy TEXT,
    parameters JSONB,
    rawRecommendation JSONB,
    sourceEvent JSONB
  );`);

  await p.query(`CREATE TABLE IF NOT EXISTS executions (
    id SERIAL PRIMARY KEY,
    eventId TEXT,
    executedAt TIMESTAMP WITH TIME ZONE,
    result JSONB
  );`);
}

async function saveProposal(p) {
  const pool = getPool();
  await pool.query(`INSERT INTO proposals (id,eventId,createdAt,confidence,risk,requiresApproval,recommendedAction,strategy,parameters,rawRecommendation,sourceEvent)
    VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
    ON CONFLICT (id) DO UPDATE SET
      confidence = EXCLUDED.confidence,
      risk = EXCLUDED.risk,
      requiresApproval = EXCLUDED.requiresApproval,
      recommendedAction = EXCLUDED.recommendedAction,
      strategy = EXCLUDED.strategy,
      parameters = EXCLUDED.parameters,
      rawRecommendation = EXCLUDED.rawRecommendation,
      sourceEvent = EXCLUDED.sourceEvent;`, [
    p.proposalId,
    p.eventId,
    p.createdAt,
    p.confidence || null,
    p.risk || null,
    p.requiresApproval || false,
    p.recommendedAction || null,
    p.strategy || null,
    p.parameters || {},
    p.rawRecommendation || {},
    p.sourceEvent || {}
  ]);
}

async function listProposals() {
  const pool = getPool();
  const res = await pool.query(`SELECT id,eventid,createdat,confidence,risk,requiresapproval,recommendedaction,strategy,parameters,rawrecommendation,sourceevent
    FROM proposals ORDER BY createdat DESC`);
  return res.rows.map(r => ({
    proposalId: r.id,
    eventId: r.eventid,
    createdAt: r.createdat,
    confidence: r.confidence,
    risk: r.risk,
    requiresApproval: r.requiresapproval,
    recommendedAction: r.recommendedaction,
    strategy: r.strategy,
    parameters: r.parameters,
    rawRecommendation: r.rawrecommendation,
    sourceEvent: r.sourceevent
  }));
}

async function recordExecution(eventId, executedAt, result) {
  const pool = getPool();
  await pool.query(`INSERT INTO executions (eventId, executedAt, result) VALUES ($1,$2,$3)`, [eventId, executedAt, result || {}]);
}

module.exports = { init, saveProposal, listProposals, recordExecution };
