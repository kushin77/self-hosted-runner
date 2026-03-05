
"use strict";

/**
 * Minimal Vault client helper.
 * Uses VAULT_ADDR and VAULT_TOKEN from env; returns JSON data from a secret path.
 * If VAULT_ADDR is not set, functions resolve to undefined.
 */
// use node-fetch explicitly so that HTTP traffic can be intercepted in tests
const fetch = require('node-fetch').default;
async function getSecret(path) {
  if (!process.env.VAULT_ADDR) {
    return undefined;
  }
  const token = process.env.VAULT_TOKEN;
  if (!token) {
    throw new Error('VAULT_TOKEN not set');
  }
  const url = `${process.env.VAULT_ADDR}/v1/${path}`;
  const res = await fetch(url, {
    method: 'GET',
    headers: {
      'X-Vault-Token': token,
    },
  });
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`vault request failed ${res.status}: ${body}`);
  }
  const data = await res.json();
  // Vault returns { data: { ... } }
  return data.data;
}

module.exports = {
  getSecret,
};
