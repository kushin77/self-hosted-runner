const fs = require('fs');
const path = require('path');

const backend = process.env.SECRETS_BACKEND || 'memory';
const filePath = process.env.SECRETS_FILE || path.join(__dirname, '..', '..', '.secrets', 'tokens.json');

let memory = [];

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
  if (backend === 'file') {
    const arr = loadFile();
    arr.push(tokenObj);
    saveFile(arr);
    return true;
  }
  memory.push(tokenObj);
  return true;
}

async function getToken(token) {
  if (backend === 'file') {
    const arr = loadFile();
    return arr.find(t => t.token === token);
  }
  return memory.find(t => t.token === token);
}

module.exports = { setToken, getToken };
