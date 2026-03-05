"use strict";

// Simple audit logger for security/compliance.
// Writes events as newline-delimited JSON to file or S3 bucket if configured.

const fs = require('fs');
const path = require('path');

const AUDIT_FILE = process.env.AUDIT_FILE || '/var/log/rc-audit.log';
const AUDIT_BUCKET = process.env.AUDIT_BUCKET; // e.g. s3://company-audit

function writeLocal(event) {
  try {
    fs.appendFileSync(AUDIT_FILE, JSON.stringify(event) + "\n");
  } catch (e) {
    console.warn('audit: failed to write local file', e.message);
  }
}

function log(event) {
  const record = {
    timestamp: new Date().toISOString(),
    ...event,
  };
  writeLocal(record);
  if (AUDIT_BUCKET) {
    // placeholder: upload to S3 via aws cli if available
    const tmp = path.join('/tmp', `audit-${Date.now()}.json`);
    try {
      fs.writeFileSync(tmp, JSON.stringify(record));
      require('child_process').execSync(`aws s3 cp ${tmp} ${AUDIT_BUCKET}/`);
      fs.unlinkSync(tmp);
    } catch (e) {
      console.warn('audit: s3 upload failed', e.message);
    }
  }
}

module.exports = { log };
