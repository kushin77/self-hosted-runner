const http = require('http');
const WebSocket = require('ws');

const API_BASE = process.env.API_BASE || 'http://localhost:3001';
const WS_URL = process.env.WS_URL || `ws://localhost:3001/ws/events`;

async function fetchEvents() {
  return new Promise((resolve, reject) => {
    http.get(`${API_BASE}/api/events`, (res) => {
      let buf = '';
      res.on('data', (d) => (buf += d));
      res.on('end', () => {
        try {
          const json = JSON.parse(buf);
          resolve(json.events || []);
        } catch (e) {
          reject(e);
        }
      });
    }).on('error', reject);
  });
}

async function wsSmoke(timeoutSec = 8) {
  return new Promise((resolve) => {
    const ws = new WebSocket(WS_URL);
    let got = 0;
    ws.on('open', () => {});
    ws.on('message', (m) => {
      try {
        const data = JSON.parse(m.toString());
        // accept either snapshot or event envelopes
        if (data && data.type === 'snapshot' && Array.isArray(data.events)) {
          data.events.forEach((ev) => validateEvent(ev));
          got += data.events.length;
        } else if (data && data.type === 'event' && data.event) {
          validateEvent(data.event);
          got++;
        } else if (data && Array.isArray(data)) {
          data.forEach((ev) => validateEvent(ev));
          got += data.length;
        } else if (data && data.id) {
          validateEvent(data);
          got++;
        }
      } catch (e) {
        // ignore parse errors here
      }
    });
    ws.on('error', () => {
      resolve({ ok: false, got });
    });
    setTimeout(() => {
      try { ws.close(); } catch (e) {}
      resolve({ ok: got > 0, got });
    }, timeoutSec * 1000);
  });
}

function validateEvent(ev) {
  if (!ev || typeof ev !== 'object') throw new Error('event not object');
  // required fields: id or time, type, severity, message/msg
  if (!(ev.id || ev.time)) throw new Error('missing id/time');
  if (typeof ev.type !== 'string') throw new Error('missing type');
  if (typeof ev.severity !== 'string') throw new Error('missing severity');
  if (!(typeof ev.message === 'string' || typeof ev.msg === 'string')) throw new Error('missing message');
  return true;
}

(async function main() {
  console.log('E2E smoke: fetching /api/events');
  try {
    const ev = await fetchEvents();
    console.log('Events length:', Array.isArray(ev) ? ev.length : 'N/A');
  } catch (e) {
    console.error('Failed to fetch events:', e.message || e);
    process.exit(2);
  }

  console.log('E2E smoke: connecting to WS events');
  const res = await wsSmoke(10);
  console.log('WS result:', res);
  if (!res.ok) {
    console.error('WS smoke failed — no messages received');
    process.exit(3);
  }

  console.log('E2E smoke passed');
  process.exit(0);
})();
