const fs = require('fs');
const path = require('path');

const simulate = process.env.SIMULATE_VAULT === '1' || false;
const filePath = process.env.VAULT_SIM_FILE || path.join(__dirname, '..', '..', '.secrets', 'vault_tokens.json');

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
  }
}

function saveFile(arr) {
  ensureDir(filePath);
  fs.writeFileSync(filePath, JSON.stringify(arr, null, 2), 'utf8');
}

async function setToken(tokenObj) {
  if (simulate) {
    const arr = loadFile();
    arr.push(tokenObj);
    saveFile(arr);
    return true;
  }
  throw new Error('Vault adapter not configured. Set SIMULATE_VAULT=1 for local testing or implement real Vault calls.');
}

async function getToken(token) {
  if (simulate) {
    const arr = loadFile();
    return arr.find(t => t.token === token);
  }
  throw new Error('Vault adapter not configured. Set SIMULATE_VAULT=1 for local testing or implement real Vault calls.');
}

module.exports = { setToken, getToken };
