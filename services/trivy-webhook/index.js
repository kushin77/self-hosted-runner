const express = require('express');
const bodyParser = require('body-parser');
const crypto = require('crypto');
const fetch = require('node-fetch');

const PORT = process.env.PORT || 8080;
const SECRET = process.env.TRIVY_WEBHOOK_SECRET || process.env.WEBHOOK_SECRET || '';
const GITHUB_TOKEN = process.env.GITHUB_TOKEN;
const REPO = process.env.DISPATCH_REPO || process.env.GITHUB_REPOSITORY;

function verifySignature(raw, signature) {
  if (!SECRET) return true;
  if (!signature) return false;
  const hmac = crypto.createHmac('sha256', SECRET).update(raw).digest('hex');
  return signature === `sha256=${hmac}`;
}

async function sendDispatch(payload) {
  if (!GITHUB_TOKEN || !REPO) {
    console.error('Missing GITHUB_TOKEN or REPO; cannot dispatch');
    return;
  }
  const url = `https://api.github.com/repos/${REPO}/dispatches`;
  const body = {
    event_type: 'trivy_alert',
    client_payload: payload
  };
  const r = await fetch(url, {
    method: 'POST',
    headers: {
      'Authorization': `token ${GITHUB_TOKEN}`,
      'Accept': 'application/vnd.github.everest-preview+json',
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(body)
  });
  if (!r.ok) console.error('Dispatch failed', r.status, await r.text());
  else console.log('Dispatch sent');
}

const app = express();
app.use(bodyParser.json({ verify: (req, res, buf) => { req.rawBody = buf } }));

app.post('/trivy-webhook', async (req, res) => {
  const sig = req.headers['x-hub-signature-256'] || req.headers['x-signature'];
  if (!verifySignature(req.rawBody, sig)) {
    console.warn('Invalid signature');
    return res.status(401).json({ ok: false });
  }
  const payload = req.body;
  // Trivy webhook may contain scanner results or image scan summary. Normalize.
  const image = payload.Target || payload.target || (payload.scan && payload.scan.image) || payload.image || 'unknown';
  // Count high/critical findings (attempt to navigate multiple Trivy JSON shapes)
  let high = 0, critical = 0;
  const vulns = [];
  function collect(node) {
    if (!node) return;
    if (Array.isArray(node)) return node.forEach(collect);
    if (node.Vulnerabilities) collect(node.Vulnerabilities);
    if (node.Severity) {
      const sev = node.Severity.toLowerCase();
      if (sev === 'high') high++;
      if (sev === 'critical') critical++;
      vulns.push({ id: node.VulnerabilityID || node.Name || node.ID, severity: node.Severity, pkg: node.PkgName || node.PackageName });
    }
  }
  collect(payload.Results || payload.result || payload.scan || payload);

  console.log(`Scan for ${image}: critical=${critical}, high=${high}`);

  // Thresholds can be configured via env
  const CRIT_T = parseInt(process.env.THRESH_CRITICAL || '1', 10);
  const HIGH_T = parseInt(process.env.THRESH_HIGH || '5', 10);

  if (critical >= CRIT_T || high >= HIGH_T) {
    await sendDispatch({ image, critical, high, vulns: vulns.slice(0, 25) });
    return res.json({ triggered: true });
  }
  res.json({ triggered: false });
});

app.get('/healthz', (req, res) => res.json({ ok: true }));

app.listen(PORT, () => console.log(`Trivy webhook listening on ${PORT}`));
