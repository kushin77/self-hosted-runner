/*
  node-pg-migrate migration: initial schema for repair proposals and executions
  Run: npx node-pg-migrate up --migrations-dir services/pipeline-repair/migrations
*/

exports.up = (pgm) => {
  pgm.sql(`CREATE EXTENSION IF NOT EXISTS "uuid-ossp";`);

  pgm.createTable('proposals', {
    id: { type: 'text', primaryKey: true },
    eventId: { type: 'text', notNull: false },
    createdAt: { type: 'timestamp with time zone', notNull: false },
    confidence: { type: 'real', notNull: false },
    risk: { type: 'text', notNull: false },
    requiresApproval: { type: 'boolean', notNull: false, default: false },
    recommendedAction: { type: 'text', notNull: false },
    strategy: { type: 'text', notNull: false },
    parameters: { type: 'jsonb', notNull: false },
    rawRecommendation: { type: 'jsonb', notNull: false },
    sourceEvent: { type: 'jsonb', notNull: false }
  });

  pgm.createTable('executions', {
    id: { type: 'serial', primaryKey: true },
    eventId: { type: 'text', notNull: false },
    executedAt: { type: 'timestamp with time zone', notNull: false },
    result: { type: 'jsonb', notNull: false }
  });
};

exports.down = (pgm) => {
  pgm.dropTable('executions');
  pgm.dropTable('proposals');
};
