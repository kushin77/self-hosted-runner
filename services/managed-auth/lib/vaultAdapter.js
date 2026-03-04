// Vault adapter for secretStore. Uses `node-vault` when configured, or falls
// back to a local simulate mode when `SIMULATE_VAULT=1`.
const path = require('path');
const fs = require('fs');

const SIMULATE = process.env.SIMULATE_VAULT === '1' || false;
const SIM_FILE = process.env.VAULT_SIM_FILE || path.join(__dirname, '..', '..', '.secrets', 'vault_tokens.json');

function ensureDir(p) {
  const dir = path.dirname(p);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
}

function loadSim() {
  try {
    if (!fs.existsSync(SIM_FILE)) return [];
    return JSON.parse(fs.readFileSync(SIM_FILE, 'utf8') || '[]');
  } catch (e) { return []; }
}

function saveSim(arr) {
  ensureDir(SIM_FILE);
  fs.writeFileSync(SIM_FILE, JSON.stringify(arr, null, 2), 'utf8');
}

let vaultClient = null;
let usingNodeVault = false;

function initVaultClient() {
  if (vaultClient || SIMULATE) return;
  try {
    const vault = require('node-vault');
    const opts = {};
    if (process.env.VAULT_ADDR) opts.endpoint = process.env.VAULT_ADDR;
    if (process.env.VAULT_TOKEN) opts.token = process.env.VAULT_TOKEN;
    vaultClient = vault(opts);
    usingNodeVault = true;
  } catch (e) {
    vaultClient = null;
    usingNodeVault = false;
  }
}

// KV mount and base path (KV v2).
const KV_MOUNT = process.env.VAULT_KV_MOUNT || 'secret';
const BASE_PATH = process.env.VAULT_KV_BASE_PATH || 'runnercloud/tokens';

function tokenPath(token) {
  // KV v2 path: `${mount}/data/${base}/${token}`
  return `${KV_MOUNT}/data/${BASE_PATH}/${token}`;
}

async function setToken(tokenObj) {
  if (SIMULATE) {
    const arr = loadSim();
    arr.push(tokenObj);
    saveSim(arr);
    return true;
  }
  initVaultClient();
  if (!usingNodeVault || !vaultClient) throw new Error('Vault client not configured. Set SIMULATE_VAULT=1 for local testing or provide VAULT_ADDR and VAULT_TOKEN and install node-vault.');
  const token = tokenObj.token;
  const p = tokenPath(token);
  // node-vault write expects { data: { ... } } for KV v2
  await vaultClient.write(p, { data: tokenObj });
  return true;
}

async function getToken(token) {
  if (SIMULATE) {
    const arr = loadSim();
    return arr.find(t => t.token === token);
  }
  initVaultClient();
  if (!usingNodeVault || !vaultClient) throw new Error('Vault client not configured. Set SIMULATE_VAULT=1 for local testing or provide VAULT_ADDR and VAULT_TOKEN and install node-vault.');
  const p = tokenPath(token);
  const resp = await vaultClient.read(p);
  // node-vault returns { data: { data: { ... } } } for KV v2 read
  if (!resp || !resp.data) return null;
  const data = resp.data.data || resp.data || null;
  if (!data) return null;
  return data;
}

module.exports = { setToken, getToken };
