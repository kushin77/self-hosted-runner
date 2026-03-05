const fs = require('fs');
const path = require('path');
const https = require('https');

const backend = process.env.SECRETS_BACKEND || 'memory';
const filePath = process.env.SECRETS_FILE || path.join(__dirname, '..', '..', '.secrets', 'tokens.json');
const vaultAddr = process.env.VAULT_ADDR || 'https://vault.example.com:8200';
const vaultNamespace = process.env.VAULT_NAMESPACE || 'admin';

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

// Vault client for AppRole auth and KV2 storage
async function getVaultToken() {
  return new Promise((resolve, reject) => {
    if (process.env.VAULT_TOKEN) {
      return resolve(process.env.VAULT_TOKEN);
    }
    
    // AppRole login if credentials provided
    const roleId = process.env.VAULT_ROLE_ID;
    const secretId = process.env.VAULT_SECRET_ID;
    
    if (!roleId || !secretId) {
      return reject(new Error('VAULT_TOKEN or (VAULT_ROLE_ID + VAULT_SECRET_ID) required'));
    }
    
    const loginPayload = JSON.stringify({ role_id: roleId, secret_id: secretId });
    const authUrl = new URL(`${vaultAddr}/v1/auth/approle/login`);
    
    const req = https.request(authUrl, {
      method: 'POST',
      headers: {
        'X-Vault-Namespace': vaultNamespace,
        'Content-Type': 'application/json',
        'Content-Length': loginPayload.length,
      },
      rejectUnauthorized: false, // dev/test only
    }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          const resp = JSON.parse(data);
          resolve(resp.auth.client_token);
        } else {
          reject(new Error(`Vault auth failed: ${res.statusCode} ${data}`));
        }
      });
    });
    
    req.on('error', reject);
    req.write(loginPayload);
    req.end();
  });
}

async function vaultWrite(path, data) {
  return new Promise((resolve, reject) => {
    getVaultToken().then(token => {
      const payload = JSON.stringify(data);
      const url = new URL(`${vaultAddr}/v1/${path}`);
      
      const req = https.request(url, {
        method: 'POST',
        headers: {
          'X-Vault-Namespace': vaultNamespace,
          'X-Vault-Token': token,
          'Content-Type': 'application/json',
          'Content-Length': payload.length,
        },
        rejectUnauthorized: false,
      }, (res) => {
        let data = '';
        res.on('data', chunk => data += chunk);
        res.on('end', () => {
          if (res.statusCode >= 200 && res.statusCode < 300) {
            resolve(JSON.parse(data));
          } else {
            reject(new Error(`Vault write failed: ${res.statusCode} ${data}`));
          }
        });
      });
      
      req.on('error', reject);
      req.write(payload);
      req.end();
    }).catch(reject);
  });
}

async function vaultRead(path) {
  return new Promise((resolve, reject) => {
    getVaultToken().then(token => {
      const url = new URL(`${vaultAddr}/v1/${path}`);
      
      const req = https.request(url, {
        method: 'GET',
        headers: {
          'X-Vault-Namespace': vaultNamespace,
          'X-Vault-Token': token,
        },
        rejectUnauthorized: false,
      }, (res) => {
        let data = '';
        res.on('data', chunk => data += chunk);
        res.on('end', () => {
          if (res.statusCode >= 200 && res.statusCode < 300) {
            resolve(JSON.parse(data));
          } else if (res.statusCode === 404) {
            resolve(null);
          } else {
            reject(new Error(`Vault read failed: ${res.statusCode} ${data}`));
          }
        });
      });
      
      req.on('error', reject);
      req.end();
    }).catch(reject);
  });
}

async function setToken(tokenObj) {
  if (backend === 'vault') {
    const secretPath = `secret/data/runnercloud/tokens/${tokenObj.token}`;
    try {
      await vaultWrite(secretPath, { data: tokenObj });
      return true;
    } catch (e) {
      console.error('Vault write failed, falling back to memory:', e.message);
      memory.push(tokenObj);
      return false;
    }
  }
  
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
  if (backend === 'vault') {
    const secretPath = `secret/data/runnercloud/tokens/${token}`;
    try {
      const resp = await vaultRead(secretPath);
      return resp ? resp.data.data : null;
    } catch (e) {
      console.error('Vault read failed, falling back to memory:', e.message);
      return memory.find(t => t.token === token);
    }
  }
  
  if (backend === 'file') {
    const arr = loadFile();
    return arr.find(t => t.token === token);
  }
  
  return memory.find(t => t.token === token);
}

module.exports = { setToken, getToken };
