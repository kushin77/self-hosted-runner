"use strict";

// NOTE: this file is now CommonJS (named logger.cjs on disk)
/**
 * Shared structured JSON logger for services.
 * Duplicate of provisioner-worker logger to keep services isolated.
 *
 * Usage: const logger = require('./logger.cjs');
 *       const log = logger.child({ correlation_id: 'xyz' });
 *
 * Environment Variables:
 *   LOG_LEVEL (info|debug|warn|error) default info
 */
const util = require('util');
const { randomUUID } = require('crypto');

const LEVELS = { error: 0, warn: 1, info: 2, debug: 3 };
const DEFAULT_LEVEL = process.env.LOG_LEVEL || 'info';
let currentLevel = LEVELS[DEFAULT_LEVEL] !== undefined ? LEVELS[DEFAULT_LEVEL] : LEVELS.info;

function formatMessage(level, msg, meta) {
  const record = {
    timestamp: new Date().toISOString(),
    level,
    message: msg,
    ...meta,
  };
  if (record.error && record.error instanceof Error) {
    record.error = record.error.stack || record.error.message;
  }
  return JSON.stringify(record);
}

function log(level, msg, meta = {}) {
  if (LEVELS[level] <= currentLevel) {
    console.log(formatMessage(level, msg, meta));
  }
}

function error(msg, meta = {}) { log('error', msg, meta); }
function warn(msg, meta = {}) { log('warn', msg, meta); }
function info(msg, meta = {}) { log('info', msg, meta); }
function debug(msg, meta = {}) { log('debug', msg, meta); }

function child(fixedMeta = {}) {
  return {
    error: (msg, meta = {}) => error(msg, { ...fixedMeta, ...meta }),
    warn: (msg, meta = {}) => warn(msg, { ...fixedMeta, ...meta }),
    info: (msg, meta = {}) => info(msg, { ...fixedMeta, ...meta }),
    debug: (msg, meta = {}) => debug(msg, { ...fixedMeta, ...meta }),
    child: (more) => child({ ...fixedMeta, ...more }),
  };
}

function genCorrelationId() {
  return randomUUID();
}

module.exports = { error, warn, info, debug, child, genCorrelationId, setLevel: (lvl) => {
  if (LEVELS[lvl] !== undefined) currentLevel = LEVELS[lvl];
}};
