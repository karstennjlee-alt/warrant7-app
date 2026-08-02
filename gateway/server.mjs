import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { Store, ORG, USER } from './lib/store.mjs';
import { policyPayload } from './lib/policy.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const PORT = Number(process.env.PORT ?? 8787);

// Dev bearer token. Real deployments put Supabase JWT verification here; this exists so the
// whole loop can be exercised without an email round-trip and a dashboard redirect allowlist.
// It is a shared secret between this process and Config.xcconfig, and it is not in git.
const DEV_TOKEN = process.env.WARRANT_DEV_TOKEN ?? 'warrant-dev-token';

const store = new Store(path.join(HERE, '.data'));

// ── Plumbing ────────────────────────────────────────────────────────────────

function send(res, status, body, headers = {}) {
  const payload = body === undefined ? '' : JSON.stringify(body);
  res.writeHead(status, {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Authorization, Content-Type, Idempotency-Key, X-Warrant-Client',
    'Access-Control-Allow-Methods': 'GET, POST, DELETE, OPTIONS',
    ...headers
  });
  res.end(payload);
}

function fail(res, status, code, message) {
  send(res, status, { code, message: message ?? code });
}

async function readJSON(req) {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  if (!chunks.length) return {};
  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  } catch {
    return {};
  }
}

function authorised(req) {
  const header = req.headers.authorization ?? '';
  return header === `Bearer ${DEV_TOKEN}`;
}

// ── Routes ──────────────────────────────────────────────────────────────────

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const { pathname } = url;
  const method = req.method ?? 'GET';

  if (method === 'OPTIONS') return send(res, 204);

  // The console, served unauthenticated so it can be opened in a browser.
  if (pathname === '/' || pathname === '/index.html' || pathname === '/app.js') {
    const name = pathname === '/app.js' ? 'app.js' : 'index.html';
    const file = path.join(HERE, 'public', name);
    if (!fs.existsSync(file)) return fail(res, 404, 'NOT_FOUND');
    res.writeHead(200, {
      'Content-Type': name.endsWith('.js') ? 'text/javascript; charset=utf-8' : 'text/html; charset=utf-8',
      'Cache-Control': 'no-store'
    });
    return res.end(fs.readFileSync(file));
  }

  // The agent and lab endpoints drive the demo from the console.
  if (pathname === '/api/agent/refund' && method === 'POST') {
    const body = await readJSON(req);
    const amountMinor = Number(body.amount_minor ?? 240_000);
    if (!Number.isInteger(amountMinor) || amountMinor <= 0) {
      return fail(res, 400, 'BAD_AMOUNT', 'amount_minor must be a positive integer');
    }
    return send(res, 200, store.submit({
      amountMinor,
      recipient: body.recipient ?? 'Northwind',
      recipientKey: (body.recipient ?? 'Northwind').toLowerCase().replace(/\s+/g, '.'),
      injected: body.injected !== false
    }));
  }

  /**
   * Act three, driven from the console: edit a stored record in place, without re-signing it.
   *
   * This is the honest version of the demo. Nothing here can make a refund happen after the
   * fact — the only thing a forger achieves is a ledger that announces it has been forged, and
   * the phone is what announces it.
   */
  if (pathname === '/api/lab/tamper' && method === 'POST') {
    const body = await readJSON(req);
    const record = store.state.receipts.find((r) => r.seq === Number(body.seq));
    if (!record) return fail(res, 404, 'NO_RECORD', 'no record with that sequence');
    record.amount_minor = Number(body.amount_minor ?? record.amount_minor * 10);
    fs.writeFileSync(path.join(HERE, '.data', 'state.json'), JSON.stringify(store.state, null, 2));
    return send(res, 200, { tampered: record.seq, now: record.amount_minor, selfCheck: store.ledger.verify(store.state.receipts) });
  }

  if (pathname === '/api/lab/selfcheck') {
    return send(res, 200, store.ledger.verify(store.state.receipts));
  }

  if (pathname === '/api/demo/reset' && method === 'POST') {
    return send(res, 200, store.reset());
  }

  // Everything under /api/v1 needs a session.
  if (!pathname.startsWith('/api/v1/')) return fail(res, 404, 'NOT_FOUND');
  if (!authorised(req)) return fail(res, 401, 'UNAUTHORIZED', 'missing or invalid session token');

  const segments = pathname.replace('/api/v1/', '').split('/');

  if (segments[0] === 'me') {
    return send(res, 200, { user: USER, organizations: [ORG] });
  }

  if (segments[0] === 'policy') {
    return send(res, 200, policyPayload());
  }

  if (segments[0] === 'actions') {
    const limit = Number(url.searchParams.get('limit') ?? 50);
    return send(res, 200, store.state.actions.slice(-limit).reverse());
  }

  if (segments[0] === 'receipts') {
    if (segments[1] === 'export') return send(res, 200, store.bundle());
    const since = url.searchParams.get('since');
    const records = since
      ? store.state.receipts.filter((r) => new Date(r.ts) > new Date(since))
      : store.state.receipts;
    return send(res, 200, records);
  }

  if (segments[0] === 'approvals') {
    if (!segments[1]) {
      return send(res, 200, store.approvals(url.searchParams.get('status')));
    }
    const id = segments[1];
    const action = segments[2];

    if (!action && method === 'GET') {
      const approval = store.approval(id);
      return approval ? send(res, 200, approval) : fail(res, 404, 'NOT_FOUND');
    }

    if ((action === 'approve' || action === 'deny') && method === 'POST') {
      const body = await readJSON(req);
      const result = store.decide({
        id,
        approve: action === 'approve',
        boundDigest: body.bound_digest,
        idempotencyKey: body.idempotency_key ?? req.headers['idempotency-key'],
        reason: body.reason,
        note: body.note
      });
      if (result.error) return fail(res, result.error, result.code);
      return send(res, 200, result.approval);
    }
  }

  if (segments[0] === 'devices') {
    if (method === 'POST') return send(res, 200, store.registerDevice(await readJSON(req)));
    if (method === 'DELETE' && segments[1]) {
      store.removeDevice(segments[1]);
      return send(res, 204);
    }
  }

  return fail(res, 404, 'NOT_FOUND');
});

server.listen(PORT, '0.0.0.0', () => {
  const check = store.ledger.verify(store.state.receipts);
  console.log(`Warrant gateway on http://localhost:${PORT}`);
  console.log(`  console        http://localhost:${PORT}/`);
  console.log(`  public key     ${store.ledger.publicKeyBase64}`);
  console.log(`  ledger         ${check.ok ? `${check.count} records, self-check passes` : `FAILING at index ${check.index} (${check.reason})`}`);
  console.log(`  dev token      ${DEV_TOKEN}`);
});
