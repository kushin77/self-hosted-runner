const fs = require('fs');
const path = require('path');

const backend = process.env.SECRETS_BACKEND || 'memory';
const filePath = process.env.SECRETS_FILE || path.join(__dirname, '..', '..', '.secrets', 'tokens.json');

let memory = [];

<<<<<<< HEAD
// If backend is vault, try to load vault adapter
if (backend === 'vault') {
  try {
    const vault = require('./vaultStore');
    module.exports = { setToken: vault.setToken, getToken: vault.getToken };
  } catch (e) {
    // fallthrough to in-process implementation that will error when used
=======
// If backend is vault, try to load the real adapter first then fall back to
// the simulate vault store. This lets CI start a real Vault dev server and
// exercise the adapter while preserving local simulate behavior.
if (backend === 'vault') {
  try {
    const vault = require('./vaultAdapter');
    module.exports = { setToken: vault.setToken, getToken: vault.getToken };
  } catch (e) {
    try {
      const vault = require('./vaultStore');
      module.exports = { setToken: vault.setToken, getToken: vault.getToken };
    } catch (e2) {
      // fallthrough to in-process implementation that will error when used
    }
>>>>>>> feature/p2-vault-ci
  }
}

function ensureDir(p) {
  const dir = path.dirname(p);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
}

function loadFile() {
  try {
    if (!fs.existsSync(filePath)) return [];
    const b = fs.readFileSync(filePath, 'utf8');
    return JSON.parse(b || '[]');
  } catch (e) {
    return [];
    // If backend is vault, try to load the real adapter first then fall back to
    // the simulate vault store. This lets CI start a real Vault dev server and
    // exercise the adapter while preserving local simulate behavior.
    if (backend === 'vault') {
      try {
        const vault = require('./vaultAdapter');
        module.exports = { setToken: vault.setToken, getToken: vault.getToken };
      } catch (e) {
        try {
          const vault = require('./vaultStore');
          module.exports = { setToken: vault.setToken, getToken: vault.getToken };
        } catch (e2) {
          // fallthrough to in-process implementation that will error when used
        }
      }
    }

module.exports = { setToken, getToken };
