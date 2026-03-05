
// Unit test for Vault helper using nock to simulate Vault HTTP API
const nock = require('nock');
const { getSecret } = require('../lib/vault');

(async () => {
  try {
    process.env.VAULT_ADDR = 'http://localhost:8200';
    process.env.VAULT_TOKEN = 'token123';

    const path = 'secret/data/test';
    const resp = { data: { token: 'abc', cert: 'CERT', key: 'KEY' } };

    nock(process.env.VAULT_ADDR)
      .get(`/v1/${path}`)
      .matchHeader('X-Vault-Token', process.env.VAULT_TOKEN)
      .reply(200, resp);

    const secret = await getSecret(path);
    if (secret.token !== 'abc' || secret.cert !== 'CERT' || secret.key !== 'KEY') {
      console.error('vault secret mismatch', secret);
      process.exit(2);
    }
    console.log('[test] vault helper returned expected data');
    process.exit(0);
  } catch (err) {
    console.error('[test] vault helper error', err);
    process.exit(1);
  }
})();
