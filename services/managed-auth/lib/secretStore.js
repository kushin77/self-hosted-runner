const fs = require('fs');
const path = require('path');

const backend = process.env.SECRETS_BACKEND || 'memory';
const filePath = process.env.SECRETS_FILE || path.join(__dirname, '..', '..', '.secrets', 'tokens.json');

function ensureDir(p) {
  const dir = path.dirname(p);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
}

function readFile() {
  try {
    if (!fs.existsSync(filePath)) return [];
    const b = fs.readFileSync(filePath, 'utf8');
    return JSON.parse(b || '[]');
  } catch (e) {
    return [];
  }
}

function writeFile(arr) {
  ensureDir(filePath);
  fs.writeFileSync(filePath, JSON.stringify(arr, null, 2), 'utf8');
}

// Memory backend
const memory = [];

async function setToken_file(tokenObj) {
  const arr = readFile();
  arr.push(tokenObj);
  writeFile(arr);
  return true;
}

async function getToken_file(token) {
  const arr = readFile();
  return arr.find(t => t && t.token === token) || null;
}

async function setToken_memory(tokenObj) {
  memory.push(tokenObj);
  return true;
}

async function getToken_memory(token) {
  return memory.find(t => t && t.token === token) || null;
}

// Vault-backed: prefer real adapter then fall back to simulate store
if (backend === 'vault') {
  try {
    const va = require('./vaultAdapter');
    module.exports = { setToken: va.setToken, getToken: va.getToken };
    return;
  } catch (e) {
    try {
      const vs = require('./vaultStore');
      module.exports = { setToken: vs.setToken, getToken: vs.getToken };
      return;
    } catch (e2) {
      // fall through to file/memory implementations
    }
  }
}

// Choose file or memory backend
if (backend === 'file') {
  module.exports = { setToken: setToken_file, getToken: getToken_file };
} else {
  module.exports = { setToken: setToken_memory, getToken: getToken_memory };
}
