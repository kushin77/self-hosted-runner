// Minimal Vault secrets client for dev/staging usage.
// Uses Vite env vars: VITE_VAULT_BASE, VITE_VAULT_TOKEN, VITE_VAULT_NAMESPACE

const VAULT_BASE = typeof import.meta !== 'undefined' && (import.meta as any).env && (import.meta as any).env.VITE_VAULT_BASE
  ? String((import.meta as any).env.VITE_VAULT_BASE)
  : 'http://localhost:8200';
const VAULT_TOKEN = typeof import.meta !== 'undefined' && (import.meta as any).env && (import.meta as any).env.VITE_VAULT_TOKEN
  ? String((import.meta as any).env.VITE_VAULT_TOKEN)
  : process.env.VITE_VAULT_TOKEN || '';
const VAULT_NAMESPACE = typeof import.meta !== 'undefined' && (import.meta as any).env && (import.meta as any).env.VITE_VAULT_NAMESPACE
  ? String((import.meta as any).env.VITE_VAULT_NAMESPACE)
  : process.env.VITE_VAULT_NAMESPACE || '';

async function request(path: string, init: RequestInit = {}) {
  const url = VAULT_BASE.replace(/\/$/, '') + path;
  const headers: Record<string, string> = Object.assign({}, (init.headers as Record<string, string>) || {});
  if (VAULT_TOKEN) headers['X-Vault-Token'] = VAULT_TOKEN;
  if (VAULT_NAMESPACE) headers['X-Vault-Namespace'] = VAULT_NAMESPACE;
  if (!headers['Content-Type'] && init.body) headers['Content-Type'] = 'application/json';
  const res = await fetch(url, Object.assign({}, init, { headers }));
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new Error(`Vault request failed ${res.status} ${res.statusText} ${text}`);
  }
  try {
    return await res.json();
  } catch (e) {
    return null;
  }
}

export async function putSecret(key: string, value: unknown) {
  return request(`/v1/secret/${encodeURIComponent(key)}`, {
    method: 'PUT',
    body: JSON.stringify({ value }),
  });
}

export async function getSecret(key: string) {
  const body = await request(`/v1/secret/${encodeURIComponent(key)}`, { method: 'GET' });
  // shim returns { value: ... }
  return body && body.value !== undefined ? body.value : body;
}

export async function deleteSecret(key: string) {
  return request(`/v1/secret/${encodeURIComponent(key)}`, { method: 'DELETE' });
}

export default { putSecret, getSecret, deleteSecret };
