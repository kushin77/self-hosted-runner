// Lightweight event schema validator for mock-server
// Usage: node validate_event_schema.js

const data = require('./data');

function validateEventSchema(evt) {
  if (!evt || typeof evt !== 'object') return 'event-not-object';
  if (typeof evt.id !== 'string') return 'missing-id';
  if (typeof evt.type !== 'string') return 'missing-type';
  if (typeof evt.timestamp !== 'number') return 'missing-timestamp';
  if (evt.runnerId && typeof evt.runnerId !== 'string') return 'invalid-runnerId';
  if (evt.jobId && typeof evt.jobId !== 'string') return 'invalid-jobId';
  if (typeof evt.message !== 'string') return 'missing-message';
  if (!['info','warning','error'].includes(evt.severity)) return 'invalid-severity';
  if (evt.metadata && typeof evt.metadata !== 'object') return 'invalid-metadata';
  return null;
}

function runValidation(sampleCount = 50) {
  console.log('Validating generated events schema...');
  for (let i = 0; i < sampleCount; i++) {
    const evt = data.generateEvent();
    const err = validateEventSchema(evt);
    if (err) {
      console.error('Schema validation failed for event:', evt);
      console.error('error:', err);
      process.exit(2);
    }
  }
  // also validate seeded events
  for (const e of data.events) {
    const err = validateEventSchema(e);
    if (err) {
      console.error('Seeded event validation failed:', e, err);
      process.exit(2);
    }
  }
  console.log('All events conform to schema (sample tested).');
}

runValidation();
