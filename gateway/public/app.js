// The web console. Same gateway, same data, same design language as the phone.
//
// One deliberate difference: this page can deny, but it cannot approve. Approving requires a
// biometric check, a browser tab cannot provide one, and an "Approve" button here that skipped
// it would quietly undo the asymmetry the whole product argues for. Denial is the safe action
// and stays available everywhere; approval happens on a device that can prove who you are.

const TOKEN = 'warrant-dev-token';
const auth = { Authorization: `Bearer ${TOKEN}`, 'X-Warrant-Client': 'web/0.1.0' };

const state = { tab: 'queue', approvals: [], receipts: [], policy: null, selected: null, report: null, verifying: false };

// ── Data ────────────────────────────────────────────────────────────────────

const api = {
  get: (path) => fetch(`/api/v1${path}`, { headers: auth }).then((r) => r.json()),
  post: (path, body, extra = {}) =>
    fetch(`/api/v1${path}`, {
      method: 'POST',
      headers: { ...auth, 'Content-Type': 'application/json', ...extra },
      body: JSON.stringify(body ?? {})
    }).then(async (r) => ({ status: r.status, body: await r.json().catch(() => ({})) })),
  plain: (path, body) =>
    fetch(path, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body ?? {}) })
      .then((r) => r.json())
};

async function refresh() {
  const [approvals, receipts, policy] = await Promise.all([
    api.get('/approvals'),
    api.get('/receipts'),
    api.get('/policy')
  ]);
  state.approvals = approvals;
  state.receipts = receipts;
  state.policy = policy;
  if (state.selected) state.selected = approvals.find((a) => a.id === state.selected.id) ?? null;
  render();
}

// ── Independent verification, in the browser ────────────────────────────────
//
// This is the same job the phone does and it is done the same way: recompute every digest from
// the record itself, re-check every link, and check every signature against the published
// public key. Nothing here trusts the server's opinion of its own ledger.

function canonicalize(value) {
  if (value === null) return 'null';
  switch (typeof value) {
    case 'boolean': return value ? 'true' : 'false';
    case 'number':
      if (!Number.isFinite(value)) throw new Error('non-finite');
      return JSON.stringify(value);
    case 'string': return JSON.stringify(value);
    case 'object': {
      if (Array.isArray(value)) return `[${value.map(canonicalize).join(',')}]`;
      // Sorted by UTF-16 code unit, and emitted directly — never stored back into an object,
      // because JS would hoist integer-like keys to the front and change the bytes.
      return `{${Object.keys(value).sort().map((k) => `${JSON.stringify(k)}:${canonicalize(value[k])}`).join(',')}}`;
    }
    default: throw new Error('unsupported');
  }
}

const hex = (buffer) => [...new Uint8Array(buffer)].map((b) => b.toString(16).padStart(2, '0')).join('');
const bytesFromHex = (s) => new Uint8Array(s.match(/../g).map((b) => parseInt(b, 16)));
const bytesFromBase64 = (s) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));

async function verifyBundle(bundle) {
  let key;
  try {
    key = await crypto.subtle.importKey('raw', bytesFromBase64(bundle.public_key), { name: 'Ed25519' }, false, ['verify']);
  } catch {
    return { unsupported: true };
  }

  const rows = [];
  let expected = '0'.repeat(64);
  let failed = null;

  for (const record of bundle.records) {
    if (failed !== null) {
      rows.push({ seq: record.seq, event: record.event, code: `UNTRUSTED_DEPENDS_ON_${failed}`, tone: 'warn' });
      continue;
    }
    const { hash, signature, ...body } = record;

    if (body.prev !== expected) {
      rows.push({ seq: record.seq, event: record.event, code: 'CHAIN_BROKEN', tone: 'bad' });
      failed = record.seq;
      continue;
    }

    const input = new Uint8Array([...bytesFromHex(body.prev), ...new TextEncoder().encode(canonicalize(body))]);
    const digest = await crypto.subtle.digest('SHA-256', input);
    const valid = await crypto.subtle.verify({ name: 'Ed25519' }, key, bytesFromBase64(signature), digest);

    if (!valid) {
      rows.push({ seq: record.seq, event: record.event, code: 'SIGNATURE_INVALID', tone: 'bad' });
      failed = record.seq;
    } else if (hex(digest) !== hash) {
      rows.push({ seq: record.seq, event: record.event, code: 'HASH_MISMATCH', tone: 'bad' });
      failed = record.seq;
    } else {
      rows.push({ seq: record.seq, event: record.event, code: 'OK', tone: 'ok' });
      expected = hash;
    }
  }
  return { rows, failed, count: bundle.records.length, key: bundle.public_key };
}

// ── Formatting ──────────────────────────────────────────────────────────────

const money = (minor, currency = 'USD') =>
  new Intl.NumberFormat('en-US', { style: 'currency', currency }).format(minor / 100);

const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

function remaining(iso) {
  const seconds = Math.max(0, Math.floor((new Date(iso) - Date.now()) / 1000));
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`;
}

function toneFor(status) {
  if (status === 'APPROVED_EXECUTED') return 'green';
  if (status === 'DENIED' || status === 'EXECUTION_FAILED') return 'red';
  if (status === 'PENDING') return 'ochre';
  return 'mute';
}

function envelopeBar(marker) {
  const p = state.policy;
  if (!p) return '';
  const scale = Math.max(p.block_limit_minor * 1.35, 650000);
  const auto = (p.auto_limit_minor / scale) * 100;
  const review = ((p.block_limit_minor - p.auto_limit_minor) / scale) * 100;
  const at = marker == null ? null : Math.min(88, Math.max(4, (marker / scale) * 100));
  return `<div class="envelope">
      <div class="bar"><i style="width:${auto}%;background:var(--green)"></i><i style="width:${review}%;background:var(--band)"></i><i style="flex:1;background:var(--red)"></i></div>
      ${at == null ? '' : `<div class="marker" style="left:${at}%">▲ ${money(marker)}</div>`}
    </div>`;
}

// ── Views ───────────────────────────────────────────────────────────────────

function queueView() {
  const pending = state.approvals.filter((a) => a.status === 'PENDING');
  const settled = state.approvals.filter((a) => a.status !== 'PENDING');

  const row = (a) => `
    <button class="card row" onclick="select('${a.id}')">
      <div class="rowhead">
        <span class="status ${toneFor(a.status)}"><i></i>${a.status === 'PENDING' ? 'Needs you' : esc(a.status.replace(/_/g, ' ').toLowerCase())}</span>
        <span class="mono mute">${esc(a.id.toUpperCase())}</span>
      </div>
      <div class="amountline"><span class="amount">${money(a.amount_minor)}</span><span class="mute">to ${esc(a.action_line.split(' to ').pop())}</span></div>
      <div class="mute small">${a.status === 'PENDING' ? `Above the automatic limit · ${remaining(a.expires_at)} left` : esc(a.denial_reason ?? a.status.replace(/_/g, ' ').toLowerCase())}</div>
    </button>`;

  if (!state.approvals.length) {
    return `<div class="empty"><div class="blob"></div><h2>Nothing needs you</h2>
      <p>Agents are working inside the automatic limit. You only hear from us when they step outside it.</p></div>`;
  }
  return pending.map(row).join('') + (settled.length ? `<div class="divider"></div>` : '') + settled.map(row).join('');
}

function cardView(a) {
  const injected = a.source_injection;
  const paragraphs = (a.source_text ?? '').split('\n\n').filter(Boolean);

  return `
  <button class="back" onclick="select(null)">← Approvals</button>
  <div class="card pad">
    <div class="cardhead">
      <div>
        <div class="mute small">Refund to ${esc(a.action_line.split(' to ').pop())}</div>
        <div class="huge">${money(a.amount_minor)}</div>
        <div class="mute small">${esc(a.reference ?? '')} · requested ${new Date(a.created_at).toLocaleTimeString()}</div>
      </div>
      ${a.status === 'PENDING' ? `<div class="ring"><span>${remaining(a.expires_at)}</span></div>` : `<span class="status ${toneFor(a.status)}"><i></i>${esc(a.status.replace(/_/g, ' ').toLowerCase())}</span>`}
    </div>

    <div class="panel">
      <div class="status ochre"><i></i>Why you were asked</div>
      ${envelopeBar(a.amount_minor)}
      <p class="mute small">Above the ${money(state.policy?.auto_limit_minor ?? 50000)} automatic limit, below the ${money(state.policy?.block_limit_minor ?? 500000)} hard stop. Deterministic policy paused it — no model was asked.</p>
    </div>

    ${a.agent_statement ? `<div class="block"><div class="label">What the agent says</div>
      <p class="quote">“${esc(a.agent_statement)}”</p>
      <div class="mono mute small">${esc(a.requested_by)} · ${esc(a.reference ?? '')}</div></div>` : ''}

    ${paragraphs.length ? `<div class="block">
      <div class="labelrow"><span class="label">The text it read</span><span class="pill red"><i></i>untrusted text</span></div>
      <div class="panel">${paragraphs.map((p) => p === injected
        ? `<div class="injected mono">${esc(p)}</div>`
        : `<p>${esc(p)}</p>`).join('')}</div>
      <p class="mute small">The highlighted line came from the customer, not from your systems. It is an instruction wearing a system voice.</p>
    </div>` : ''}

    <div class="block">
      <div class="label">What a signature binds to</div>
      <div class="panel kv">
        ${[['resource', a.resource], ['amount', `${a.amount_minor} ${a.currency} (minor units)`],
           ['recipient', a.action_line.split(' to ').pop()], ['impact', a.impact],
           ['reversibility', a.reversibility], ['expires', a.expires_at], ['digest', a.bound_digest]]
          .map(([k, v]) => `<div><span>${esc(k)}</span><b class="mono">${esc(v)}</b></div>`).join('')}
      </div>
      <p class="mute small">Change any of it after signing — amount, recipient, expiry — and execution is refused with <code>DIGEST_MISMATCH</code>.</p>
    </div>

    ${a.status === 'PENDING' ? `
    <div class="actions">
      <div class="denybox">
        <select id="reason">
          <option value="PROMPT_INJECTION">Prompt injection in the request</option>
          <option value="EXCEEDS_ORDER_VALUE">Amount exceeds the order value</option>
          <option value="NEEDS_SUPERVISOR">Needs a supervisor, not me</option>
          <option value="NOT_VALID">Not a valid case</option>
        </select>
        <button class="deny" onclick="deny('${a.id}')">Deny and sign</button>
      </div>
      <div class="noapprove">
        <b>Approving happens on the phone.</b>
        A browser cannot check that it is you, and an approve button here that skipped that would
        undo the one asymmetry this product is built on. Denial is the safe action, so it stays here.
      </div>
    </div>` : `<div class="settled mono">${esc(a.status)}${a.receipt_sequence ? ` · receipt ${String(a.receipt_sequence).padStart(2, '0')}` : ''}</div>`}
  </div>`;
}

function receiptsView() {
  if (!state.receipts.length) return `<div class="empty"><p>No records yet. Fire an action from the agent panel.</p></div>`;
  const verdicts = new Map((state.report?.rows ?? []).map((r) => [r.seq, r]));
  return state.receipts.map((r) => {
    const v = verdicts.get(r.seq);
    const bad = v && v.tone === 'bad';
    return `<div class="card row ${bad ? 'broken' : ''}">
      <div class="rowhead">
        <span class="status ${bad ? 'red' : (['DENIED', 'BLOCKED', 'EXPIRED'].includes(r.event) ? 'red' : 'ink')}"><i></i>${esc(r.event)}</span>
        <span class="mute small">${r.amount_minor ? money(r.amount_minor) : ''}</span>
        <span class="mono mute" style="margin-left:auto">${String(r.seq).padStart(2, '0')} · ${new Date(r.ts).toLocaleTimeString()}</span>
      </div>
      <div class="mono mute small break">${esc(r.hash)}</div>
      ${v ? `<div class="mono small ${v.tone}">${esc(v.code)}</div>` : ''}
    </div>`;
  }).join('');
}

function verifyView() {
  const rep = state.report;
  if (state.verifying) return `<div class="empty"><p>Recomputing in this browser…</p></div>`;
  if (!rep) {
    return `<div class="card pad">
      <div class="label">Check the evidence here</div>
      <p class="mute">This page recomputes every digest and checks every signature with WebCrypto, against the published public key. It is a second, independent verifier — the phone is the third.</p>
      <button class="primary" onclick="runVerify()">Verify with public key</button>
    </div>`;
  }
  if (rep.unsupported) {
    return `<div class="card pad"><p class="bad">This browser has no Ed25519 in WebCrypto. Safari 17+ or a recent Chrome will do it — or use the phone, which never needed a browser.</p>
      <button onclick="state.report=null;render()">Back</button></div>`;
  }
  const ok = rep.failed === null;
  return `<div class="card pad">
    <span class="pill ${ok ? 'green' : 'red'}"><i></i>${ok ? 'Chain verified' : 'Verification failed'}</span>
    <h2 class="verifyhead">${ok ? 'Every record checks out' : `Record ${String(rep.failed).padStart(2, '0')} has been altered`}</h2>
    <p class="mute">${ok
      ? 'Each digest recomputed here, each link re-checked here, each signature valid under the published key.'
      : 'It no longer matches its signature, so every record after it is untrusted. The edit created and reversed nothing — the ledger simply announced it.'}</p>
    <div class="mono mute small">${rep.count} records · key ${esc(rep.key.slice(0, 12))}…</div>
    <div class="verifyrows">${rep.rows.map((r) => `<div class="vrow ${r.tone}">
        <span class="mono mute">${String(r.seq).padStart(2, '0')}</span><span>${esc(r.event)}</span><b>${esc(r.code)}</b></div>`).join('')}</div>
    <button onclick="state.report=null;render()">Check again</button>
  </div>`;
}

function limitsView() {
  const p = state.policy;
  if (!p) return '';
  return `<div class="card pad">
      <div class="label">${esc(p.resource)} · v${p.version}</div>
      <h2 class="verifyhead">${esc(p.readable_rule)}</h2>
      ${envelopeBar(null)}
      <div class="legend">
        <span><i style="background:var(--green)"></i>Auto up to ${money(p.auto_limit_minor)}</span>
        <span><i style="background:var(--band)"></i>Ask a human</span>
        <span><i style="background:var(--red)"></i>Blocked past ${money(p.block_limit_minor)}</span>
      </div>
    </div>
    <div class="card pad"><div class="label">Fixed in code — no device can change these</div>
      <ul class="locked">
        <li>The agent cannot import, hold, or reach the provider credential. Only the executor can.</li>
        <li>Any failure in identity, policy, signing, or digest checking means no execution. Never a default allow.</li>
        <li>An approval binds to one exact digest and is spendable once.</li>
        <li>No model is ever asked whether an action is safe.</li>
      </ul></div>`;
}

function labView() {
  return `<div class="card pad">
    <div class="label">The agent tries something</div>
    <div class="agentrow">
      <button onclick="fire(12000,'P. Novak',false)"><b>$120.00</b><span>inside the limit — executes, nobody paged</span></button>
      <button class="primary" onclick="fire(240000,'Northwind',true)"><b>$2,400.00</b><span>prompt-injected — pauses for a human</span></button>
      <button onclick="fire(890000,'K. Mensah',false)"><b>$8,900.00</b><span>above the hard stop — blocked</span></button>
    </div>
  </div>
  <div class="card pad">
    <div class="label">Act three — edit the evidence</div>
    <div class="agentrow">
      <button class="danger" onclick="tamper()"><b>Alter a stored record</b><span>changes an amount in place, without re-signing</span></button>
      <button onclick="resetAll()"><b>Reset</b><span>clears approvals and the ledger</span></button>
    </div>
    <p class="mute small">Then hit Verify — here, or on the phone with the network off. Nothing here can make a refund happen after the fact.</p>
  </div>`;
}

// ── Actions ─────────────────────────────────────────────────────────────────

window.select = (id) => { state.selected = id ? state.approvals.find((a) => a.id === id) : null; render(); };
window.go = (tab) => { state.tab = tab; state.selected = null; render(); };

window.deny = async (id) => {
  const approval = state.approvals.find((a) => a.id === id);
  const reason = document.getElementById('reason')?.value;
  const result = await api.post(`/approvals/${id}/deny`, {
    bound_digest: approval.bound_digest,
    idempotency_key: `web-${id}`,
    reason
  }, { 'Idempotency-Key': `web-${id}` });
  if (result.status !== 200) alert(messageFor(result.body.code));
  state.report = null;
  await refresh();
};

function messageFor(code) {
  return ({
    APPROVAL_EXPIRED: 'This request expired. The agent will need to submit a new one.',
    ALREADY_CONSUMED: 'Already decided. Someone on your team answered this first.',
    DIGEST_MISMATCH: 'The request changed after it was sent to you. Nothing was executed.'
  })[code] ?? "Couldn't complete that. Nothing was approved.";
}

window.fire = async (amount_minor, recipient, injected) => {
  await api.plain('/api/agent/refund', { amount_minor, recipient, injected });
  state.report = null;
  state.tab = 'queue';
  await refresh();
};

window.tamper = async () => {
  const last = state.receipts.at(-1);
  if (!last) return;
  await api.plain('/api/lab/tamper', { seq: last.seq, amount_minor: 24000000 });
  state.report = null;
  state.tab = 'verify';
  await refresh();
};

window.resetAll = async () => {
  await api.plain('/api/demo/reset');
  state.report = null;
  state.selected = null;
  await refresh();
};

window.runVerify = async () => {
  state.verifying = true;
  render();
  const bundle = await api.get('/receipts/export');
  state.report = await verifyBundle(bundle);
  state.verifying = false;
  render();
};

// ── Render ──────────────────────────────────────────────────────────────────

const TABS = [['queue', 'Queue'], ['receipts', 'Receipts'], ['verify', 'Verify'], ['limits', 'Limits'], ['lab', 'Lab']];

function render() {
  const pending = state.approvals.filter((a) => a.status === 'PENDING').length;
  document.getElementById('tabs').innerHTML = TABS.map(([id, label]) =>
    `<button class="${state.tab === id ? 'on' : ''}" onclick="go('${id}')">${label}${id === 'queue' && pending ? `<b class="badge">${pending}</b>` : ''}</button>`).join('');

  const heads = {
    queue: ['Approvals', pending ? `${pending} request${pending === 1 ? '' : 's'} waiting on a person` : 'Nothing waiting'],
    receipts: ['Receipts', 'Each record hashes the one before it.'],
    verify: ['Verify', 'Recomputed in this browser, against the published key.'],
    limits: ['Limits', 'What a human may move, and what nobody may.'],
    lab: ['Console', 'Stands in for the agent and the operator.']
  };
  const [title, sub] = heads[state.tab];
  document.getElementById('title').textContent = title;
  document.getElementById('sub').textContent = sub;

  const body =
    state.tab === 'queue' ? (state.selected ? cardView(state.selected) : queueView())
    : state.tab === 'receipts' ? receiptsView()
    : state.tab === 'verify' ? verifyView()
    : state.tab === 'limits' ? limitsView()
    : labView();

  document.getElementById('main').innerHTML = body;
}

refresh();
// Realtime plus polling on the phone; here the poll alone is enough — the countdown and the
// queue both have to stay honest while somebody watches them.
setInterval(() => { if (!state.verifying) refresh(); }, 1000);
