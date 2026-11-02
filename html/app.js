/* Trucking Co. company tablet */
'use strict';

const S = {
  cfg: null,
  app: 'home',
  extra: null,
  inOffice: false,
  dash: null,
  sel: {},        // per-view selection
  view: {},       // per-view sub-state (e.g. fleet dealer toggle)
};

const IS_FIVEM = typeof GetParentResourceName === 'function';
const RES = IS_FIVEM ? GetParentResourceName() : 'bdev-trucking-company';

// surface UI errors in the game's F8 console
window.addEventListener('error', (e) => {
  if (IS_FIVEM) fetch(`https://${RES}/nuiError`, { method: 'POST', body: JSON.stringify({ msg: `${e.message} @ ${e.filename}:${e.lineno}` }) }).catch(() => {});
});
window.addEventListener('unhandledrejection', (e) => {
  if (IS_FIVEM) fetch(`https://${RES}/nuiError`, { method: 'POST', body: JSON.stringify({ msg: String(e.reason && (e.reason.stack || e.reason)) }) }).catch(() => {});
});

async function post(endpoint, data) {
  if (window.TC_MOCK) return window.TC_MOCK.post(endpoint, data);
  try {
    const r = await fetch(`https://${RES}/${endpoint}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(data || {}),
    });
    return await r.json();
  } catch (e) {
    return { ok: false, msg: 'Connection error.' };
  }
}
const call = (name, ...args) => post('call', { name, args });

/* ---------------- helpers ---------------- */
const $ = (s) => document.querySelector(s);
const esc = (t) => String(t ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
function money(n) {
  n = Math.floor(Number(n) || 0);
  return (n < 0 ? '-' : '') + (S.cfg ? S.cfg.currency : '$') + Math.abs(n).toLocaleString('en-US');
}
function dur(sec) {
  sec = Math.max(0, Math.floor(sec || 0));
  if (sec >= 3600) return `${Math.floor(sec / 3600)}h ${String(Math.floor((sec % 3600) / 60)).padStart(2, '0')}m`;
  if (sec >= 60) return `${Math.floor(sec / 60)}m ${String(sec % 60).padStart(2, '0')}s`;
  return `${sec}s`;
}
const obj = (v) => (v && !Array.isArray(v) ? v : {});
const arr = (v) => (Array.isArray(v) ? v : v ? Object.values(v) : []);
const cap = (s) => String(s || '').replace(/^./, (c) => c.toUpperCase());
function can(perm) {
  const role = S.dash && S.dash.role;
  if (role === 'owner') return true;
  const p = S.cfg && S.cfg.perms[role];
  return !!(p && p[perm]);
}
function certNames(list) {
  const out = arr(list).map((k) => (S.cfg.certifications[k] ? S.cfg.certifications[k].label : k));
  return out.length ? out.join(', ') : 'None';
}
function certsOf(map) { return Object.keys(obj(map)); }
const healthColor = (h) => (h > 60 ? 'green' : h > S.cfg.fleet.minDispatchCondition ? 'yellow' : 'red');
const truckImg = (model) => `https://docs.fivem.net/vehicles/${model}.webp`;

/* action registry: data-act="id" -> fn(el, event) */
let ACTS = {};
let actSeq = 0;
function act(fn) { const id = 'a' + (++actSeq); ACTS[id] = fn; return `data-act="${id}"`; }
document.addEventListener('click', (e) => {
  const el = e.target.closest('[data-act]');
  if (el && ACTS[el.dataset.act] && !el.disabled) ACTS[el.dataset.act](el, e);
});
document.addEventListener('change', (e) => {
  const el = e.target.closest('[data-change]');
  if (el && ACTS[el.dataset.change]) ACTS[el.dataset.change](el, e);
});
function onChange(fn) { const id = 'a' + (++actSeq); ACTS[id] = fn; return `data-change="${id}"`; }

/* countdowns: <span data-count="secs"> */
let countBase = Date.now();
function tickClock() {
  const d = new Date();
  $('#clock').textContent = `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
}
setInterval(() => {
  const el = document.querySelectorAll('[data-count]');
  const passed = (Date.now() - countBase) / 1000;
  el.forEach((e) => {
    const left = Number(e.dataset.count) - passed;
    e.textContent = left <= 0 && e.dataset.zero ? e.dataset.zero : dur(left);
  });
  tickClock();
}, 1000);
const count = (secs, zero) => `<span data-count="${Math.floor(secs || 0)}"${zero ? ` data-zero="${esc(zero)}"` : ''}>${secs <= 0 && zero ? esc(zero) : dur(secs)}</span>`;

/* toasts + modal */
function toast(msg, ok = true) {
  if (!msg) return;
  const t = document.createElement('div');
  t.className = 'toast' + (ok ? '' : ' err');
  t.textContent = msg;
  $('#toasts').appendChild(t);
  setTimeout(() => t.remove(), 4200);
}
function confirmBox(title, html, okLabel = 'Confirm', danger = false) {
  return new Promise((resolve) => {
    const m = $('#modal');
    m.innerHTML = `<div class="box"><h2>${esc(title)}</h2><p>${html}</p><div class="actions">
      <button class="btn ghost" id="m-no">Cancel</button><button class="btn ${danger ? 'danger' : 'primary'}" id="m-yes">${esc(okLabel)}</button></div></div>`;
    m.classList.remove('hidden');
    const done = (v) => { m.classList.add('hidden'); m.innerHTML = ''; resolve(v); };
    $('#m-no').onclick = () => done(false);
    $('#m-yes').onclick = () => done(true);
  });
}
/** run a server action, toast its message, refresh the view on success */
async function run(name, ...args) {
  const res = await call(name, ...args);
  toast(res && res.msg, res && res.ok);
  if (res && res.ok) await render();
  return res || {};
}

/* ---------------- shell ---------------- */
const APPS = [
  { id: 'home', label: 'Dashboard', icon: 'gauge-high', perm: 'view' },
  { id: 'finance', label: 'Finances', icon: 'sack-dollar', perm: 'view' },
  { id: 'board', label: 'Bid Board', icon: 'clipboard-list', perm: 'view' },
  { id: 'loads', label: 'Loads', icon: 'route', perm: 'view' },
  { id: 'employees', label: 'Staff', icon: 'users', perm: 'view' },
  { id: 'hire', label: 'Hiring', icon: 'user-plus', perm: 'hire' },
  { id: 'fleet', label: 'Fleet', icon: 'truck', perm: 'view' },
  { id: 'upgrades', label: 'Office', icon: 'hammer', perm: 'upgrades' },
  { id: 'dispatch', label: 'Dispatch', icon: 'robot', perm: 'settings' },
  { id: 'driver', label: 'My Shift', icon: 'id-card', perm: null },
  { id: 'owner', label: 'Owner', icon: 'crown', perm: 'owner' },
];
function appVisible(a) {
  if (!S.dash) return a.id === 'driver';
  if (a.perm === 'owner') return S.dash.role === 'owner';
  if (a.id === 'driver') return S.dash.onRoster;
  return !a.perm || can(a.perm);
}
function sidebar() {
  const sb = $('#sidebar');
  if (S.app === 'listing') { sb.classList.add('hidden'); return; }
  sb.classList.remove('hidden');
  let h = `<div class="brand"><div class="logo"><i class="fa-solid fa-truck-fast"></i></div><div><b>${esc(S.dash ? S.dash.name : 'Trucking Co.')}</b><small>${esc(S.dash ? cap(S.dash.role) : 'Driver portal')}</small></div></div>`;
  APPS.filter(appVisible).forEach((a) => {
    h += `<div class="nav ${S.app === a.id ? 'active' : ''}" ${act(() => go(a.id))}><i class="fa-solid fa-${a.icon}"></i>${a.label}</div>`;
  });
  h += `<div class="spacer"></div>`;
  if (S.inOffice) h += `<div class="nav exit" ${act(() => post('leaveOffice'))}><i class="fa-solid fa-door-open"></i>Leave office</div>`;
  h += `<div class="nav exit" ${act(close)}><i class="fa-solid fa-power-off"></i>Close tablet</div>`;
  sb.innerHTML = h;
  $('#sb-company').textContent = S.dash ? `${S.dash.name} • ${money(S.dash.balance)}` : '';
}
async function go(app) { S.app = app; await render(); }
function close() { post('close'); }

async function render() {
  ACTS = {};
  countBase = Date.now();
  const c = $('#content');
  if (S.app !== 'listing') {
    const res = await call('getDashboard');
    S.dash = res && res.ok ? res.data : null;
    if (!S.dash && S.app !== 'driver') S.app = 'driver';
  }
  sidebar();
  const view = VIEWS[S.app] || VIEWS.home;
  try {
    c.innerHTML = await view();
  } catch (e) {
    console.error(e);
    c.innerHTML = `<div class="empty"><i class="fa-solid fa-triangle-exclamation"></i>Something went wrong loading this page.</div>`;
  }
  sidebar(); // re-bind after view (ACTS reset)
}

const head = (title, sub, tools = '') => `<div class="head"><div><h1>${esc(title)}</h1>${sub ? `<p>${sub}</p>` : ''}</div><div class="tools">${tools}</div></div>`;
const empty = (icon, text) => `<div class="empty"><i class="fa-solid fa-${icon}"></i>${text}</div>`;
const fail = (res) => empty('lock', esc((res && res.msg) || 'Unavailable.'));

/* ---------------- views ---------------- */
const VIEWS = {};

VIEWS.home = async () => {
  const d = S.dash;
  if (!d) return empty('briefcase', 'You do not work for a trucking company.');
  const c = d.counts || {};
  const e = d.effects || {};
  let h = head(`Good to see you`, `${esc(d.property)} • ${cap(d.role)}`);
  if (d.suspended) h += `<div class="banner red"><i class="fa-solid fa-ban"></i>Company is overdrawn past ${money(S.cfg.overdraftLimit)} and suspended from bidding. Deposit funds in Finances.</div>`;
  else if (d.balance < 0) h += `<div class="banner yellow"><i class="fa-solid fa-triangle-exclamation"></i>The company account is negative. Payroll will keep drawing it down.</div>`;
  h += `<div class="grid g4">
    <div class="card click stat" ${act(() => go('finance'))}><div class="k"><i class="fa-solid fa-building-columns"></i>Company balance</div><div class="v ${d.balance < 0 ? 'neg' : ''}">${money(d.balance)}</div><div class="s">Tap to manage funds</div></div>
    <div class="card stat"><div class="k"><i class="fa-solid fa-star"></i>Reputation</div><div class="v">${d.reputation}<span class="muted small">/100</span></div><div class="bar"><div style="width:${d.reputation}%"></div></div></div>
    <div class="card stat"><div class="k"><i class="fa-solid fa-clock"></i>Next payroll</div><div class="v">${count(d.nextPayroll, 'due')}</div><div class="s">every ${S.cfg.payrollMinutes} min</div></div>
    <div class="card click stat" ${act(() => go('loads'))}><div class="k"><i class="fa-solid fa-route"></i>Active loads</div><div class="v">${c.active || 0}</div><div class="s">${c.completed || 0} completed</div></div>
  </div>
  <div class="grid g4 mt12">
    <div class="card click stat" ${act(() => go('employees'))}><div class="k"><i class="fa-solid fa-users"></i>Staff</div><div class="v">${c.employees || 0}<span class="muted small"> / ${e.maxEmployees}</span></div><div class="s">${c.drivers || 0} drivers • ${c.dispatchers || 0} dispatchers</div></div>
    <div class="card click stat" ${act(() => go('fleet'))}><div class="k"><i class="fa-solid fa-truck"></i>Fleet</div><div class="v">${c.trucks || 0}<span class="muted small"> / ${e.maxTrucks}</span></div><div class="s">trucks in the yard</div></div>
    <div class="card click stat" ${act(() => go('board'))}><div class="k"><i class="fa-solid fa-gavel"></i>Open bids</div><div class="v">${c.bids || 0}</div><div class="s">on the bid board</div></div>
    <div class="card click stat" ${act(() => go('dispatch'))}><div class="k"><i class="fa-solid fa-robot"></i>Automation</div><div class="v small" style="font-size:16px;margin-top:6px">${d.settings.autoBid ? 'Auto-bid' : 'Manual bids'}<br>${d.settings.autoAssign ? 'Auto-assign' : 'Manual assign'}</div></div>
  </div>`;
  h += `<div class="card mt16"><h3>Quick actions</h3><div class="row wrap">
    ${can('deposit') ? `<button class="btn primary" ${act(() => go('finance'))}><i class="fa-solid fa-arrow-down"></i>Deposit funds</button>` : ''}
    <button class="btn" ${act(() => go('board'))}><i class="fa-solid fa-clipboard-list"></i>Bid on loads</button>
    ${can('hire') ? `<button class="btn" ${act(() => go('hire'))}><i class="fa-solid fa-user-plus"></i>Hire staff</button>` : ''}
    ${can('fleet') ? `<button class="btn" ${act(() => { S.view.dealer = true; go('fleet'); })}><i class="fa-solid fa-cart-shopping"></i>Buy a truck</button>` : ''}
    ${d.onRoster ? `<button class="btn" ${act(() => go('driver'))}><i class="fa-solid fa-id-card"></i>My shift</button>` : ''}
  </div></div>`;
  return h;
};

/* ----- Finances ----- */
VIEWS.finance = async () => {
  const d = S.dash;
  const owner = d.role === 'owner';
  let h = head('Finances', 'Company money is separate from your personal bank. Every purchase, wage and payout runs through this account.');
  h += `<div class="split"><div>`;
  h += `<div class="card"><h3>Company account</h3><div class="balance-big ${d.balance < 0 ? 'negc' : ''}">${money(d.balance)}</div>
    <div class="muted small mt8">Overdraft limit ${money(S.cfg.overdraftLimit)} • next payroll in ${count(d.nextPayroll, 'now')}</div></div>`;
  if (can('deposit') || owner) {
    h += `<div class="grid g2 mt12">`;
    if (can('deposit')) h += `<div class="card"><h3>Deposit</h3><div class="field"><label>From your personal bank</label><div class="money-input"><span>${esc(S.cfg.currency)}</span><input class="input" id="dep" type="number" min="1" placeholder="0"></div></div>
      <button class="btn primary block" ${act(async () => { const v = Number($('#dep').value); if (v > 0) await run('deposit', v); })}><i class="fa-solid fa-arrow-down"></i>Deposit</button></div>`;
    if (owner) h += `<div class="card"><h3>Withdraw</h3><div class="field"><label>To your personal bank</label><div class="money-input"><span>${esc(S.cfg.currency)}</span><input class="input" id="wd" type="number" min="1" placeholder="0"></div></div>
      <button class="btn block" ${act(async () => { const v = Number($('#wd').value); if (v > 0) await run('withdraw', v); })}><i class="fa-solid fa-arrow-up"></i>Withdraw</button></div>`;
    h += `</div>`;
  }
  h += `<div class="card mt12"><h3>Where the money goes</h3><div class="kv">
    <div class="k">Income</div><div class="v">Delivered loads, insurance claims, sold trucks</div>
    <div class="k">Every payroll</div><div class="v">Wages, insurance premiums, property upkeep</div>
    <div class="k">One-off</div><div class="v">Trucks, repairs, training, recruiter fees, upgrades</div>
    <div class="k">Penalties</div><div class="v">Failed loads, truck recovery, driver commission</div>
  </div></div>`;
  h += `</div><div>`;
  if (can('finance')) {
    const res = await call('getLedger');
    const rows = res.ok ? arr(res.data) : [];
    h += `<div class="card"><h3>Ledger <span class="chip">last ${rows.length}</span></h3>`;
    h += rows.length ? `<table class="ledger">${rows.map((r) => `<tr><td class="when">${esc(r.ts)}</td><td>${esc(r.reason)}</td><td class="amt ${r.amount >= 0 ? 'pos' : 'negc'}">${r.amount >= 0 ? '+' : ''}${money(r.amount)}</td></tr>`).join('')}</table>` : empty('receipt', 'No transactions yet.');
    h += `</div>`;
  } else {
    h += `<div class="card">${empty('lock', 'Only owners and managers can see the ledger.')}</div>`;
  }
  h += `</div></div>`;
  return h;
};

/* ----- Bid board ----- */
VIEWS.board = async () => {
  const res = await call('getBoard');
  if (!res.ok) return fail(res);
  const d = res.data;
  const list = arr(d.list);
  let h = head('Bid Board', `Lowest effective bid wins when bidding closes. Your reputation <b>${d.reputation}</b> gives you an edge, and rival companies bid too.`,
    `<span class="chip accent"><i class="fa-solid fa-star"></i>Rep ${d.reputation}</span>`);
  if (d.suspended) h += `<div class="banner red"><i class="fa-solid fa-ban"></i>Suspended for debt. Bidding is disabled.</div>`;
  if (!list.length) return h + empty('clipboard', 'No loads posted right now. Check back in a minute.');
  let sel = list.find((c) => c.id === S.sel.board) || list[0];
  S.sel.board = sel.id;
  h += `<div class="split"><div class="list">`;
  list.forEach((c) => {
    h += `<div class="item click ${c.id === sel.id ? 'sel' : ''} ${c.eligible ? '' : 'locked'}" ${act(() => { S.sel.board = c.id; render(); })}>
      <div class="ic ${c.my_bid ? 'green' : 'accent'}"><i class="fa-solid fa-${c.class === 'semi' ? 'trailer' : 'box'}"></i></div>
      <div class="main"><div class="t">#${c.id} ${esc(c.cargoLabel)} → ${esc(c.dropoff.label)}</div>
      <div class="d">${c.distance.toFixed(1)} km • closes in ${count(c.closesIn, 'closed')} • ${c.bid_count} bid${c.bid_count === 1 ? '' : 's'}</div></div>
      <div class="end"><div class="bold">${money(c.max_pay)}</div>${c.my_bid ? `<span class="chip green">your bid ${money(c.my_bid)}</span>` : c.eligible ? '' : `<span class="chip">rep ${c.minRep}</span>`}</div></div>`;
  });
  h += `</div><div class="card">`;
  const minBid = Math.floor(sel.max_pay * d.minBidPct);
  const start = sel.my_bid || Math.floor(sel.max_pay * 0.9 / 50) * 50;
  h += `<h3>Load #${sel.id} <span class="chip ${sel.class === 'semi' ? 'blue' : 'accent'}">${sel.class === 'semi' ? 'Semi + trailer' : 'Box truck'}</span></h3>
    <div style="font-size:18px;font-weight:700">${esc(sel.cargoLabel)}</div>
    <div class="muted mt8"><i class="fa-solid fa-location-dot"></i> ${esc(sel.pickup.label)} &nbsp;→&nbsp; <i class="fa-solid fa-flag-checkered"></i> ${esc(sel.dropoff.label)}</div>
    <div class="kv mt16">
      <div class="k">Max pay</div><div class="v">${money(sel.max_pay)}</div>
      <div class="k">Distance</div><div class="v">${sel.distance.toFixed(1)} km</div>
      <div class="k">Required certs</div><div class="v">${esc(certNames(sel.certs))}</div>
      <div class="k">Min. reputation</div><div class="v">${sel.minRep}</div>
      <div class="k">Bidding closes</div><div class="v">${count(sel.closesIn, 'closed')}</div>
    </div>`;
  if (!can('bid')) h += `<div class="banner blue mt16"><i class="fa-solid fa-circle-info"></i>Only dispatchers, managers and the owner can bid.</div>`;
  else if (!sel.eligible) h += `<div class="banner yellow mt16"><i class="fa-solid fa-lock"></i>Requires ${sel.minRep} reputation.</div>`;
  else {
    h += `<div class="field mt16"><label>Your price (${money(minBid)} – ${money(sel.max_pay)})</label>
      <input type="range" id="bidr" min="${minBid}" max="${sel.max_pay}" step="50" value="${start}" oninput="document.getElementById('bidn').value=this.value">
      <div class="money-input mt8"><span>${esc(S.cfg.currency)}</span><input class="input" id="bidn" type="number" value="${start}" oninput="document.getElementById('bidr').value=this.value"></div></div>
      <div class="row"><button class="btn primary" style="flex:1;justify-content:center" ${act(() => run('placeBid', sel.id, Number($('#bidn').value)))}><i class="fa-solid fa-gavel"></i>${sel.my_bid ? 'Update bid' : 'Place bid'}</button>
      ${sel.my_bid ? `<button class="btn danger" ${act(() => run('withdrawBid', sel.id))}>Withdraw</button>` : ''}</div>`;
  }
  h += `</div></div>`;
  return h;
};

/* ----- Loads ----- */
const LOAD_STATUS = {
  awarded: ['Needs driver', 'yellow'], assigned: ['Assigned', 'blue'], in_progress: ['In transit', 'accent'],
  delivered: ['Delivered', 'green'], completed: ['Completed', 'green'], failed: ['Failed', 'red'],
};
VIEWS.loads = async () => {
  const res = await call('getMyContracts');
  if (!res.ok) return fail(res);
  const list = arr(res.data);
  let h = head('Loads', 'Won contracts and their progress. Loads need a driver and truck before the accept window runs out.');
  if (!list.length) return h + empty('route', 'No loads yet. Win bids on the Bid Board to get work.');
  h += `<div class="list">`;
  list.forEach((c) => {
    const [label, color] = LOAD_STATUS[c.status] || [c.status, ''];
    let info = `${c.distance.toFixed(1)} km`;
    if (c.driver_name) info += ` • <i class="fa-solid fa-user"></i> ${esc(c.driver_name)}`;
    if (c.truck_plate) info += ` • <i class="fa-solid fa-truck"></i> ${esc(c.truck_plate)}`;
    if (c.status === 'awarded' && c.acceptIn != null) info += ` • assign within ${count(c.acceptIn, 'expired')}`;
    if (c.status === 'in_progress' && c.etaIn != null) info += ` • ETA ${count(c.etaIn, 'arriving')}`;
    if (['awarded', 'assigned', 'in_progress'].includes(c.status) && c.deadlineIn != null) info += ` • due ${count(c.deadlineIn, 'LATE')}`;
    let btn = '';
    if (c.status === 'awarded' && can('assign')) btn = `<button class="btn primary sm" ${act(() => assignModal(c))}><i class="fa-solid fa-user-plus"></i>Assign</button>`;
    if (c.status === 'assigned' && can('assign')) btn = `<button class="btn sm danger" ${act(async () => { if (await confirmBox('Unassign load', `Pull load <b>#${c.id}</b> from ${esc(c.driver_name || 'the driver')}?`)) run('unassignContract', c.id); })}>Unassign</button>`;
    h += `<div class="item"><div class="ic ${color}"><i class="fa-solid fa-${c.status === 'completed' ? 'circle-check' : c.status === 'failed' ? 'circle-xmark' : 'truck-fast'}"></i></div>
      <div class="main"><div class="t">#${c.id} ${esc(c.cargoLabel)} → ${esc(c.dropoff.label)}</div><div class="d">${info}</div></div>
      <div class="end"><div class="bold">${money(c.award_amount)}</div><span class="chip ${color}">${label}</span></div>${btn}</div>`;
  });
  return h + `</div>`;
};

async function assignModal(c) {
  const res = await call('getAssignOptions', c.id);
  if (!res.ok) return toast(res.msg, false);
  const drivers = arr(res.data.drivers);
  const trucks = arr(res.data.trucks);
  if (!drivers.length) return toast('No idle, qualified driver available (players must be online).', false);
  if (!trucks.length) return toast(`No available ${c.class === 'semi' ? 'semi' : 'box'} truck in good condition.`, false);
  const m = $('#modal');
  m.innerHTML = `<div class="box"><h2>Assign load #${c.id}</h2><p>${esc(c.cargoLabel)} → ${esc(c.dropoff.label)} • needs ${esc(certNames(c.certs))}</p>
    <div class="field mt12"><label>Driver</label><select class="input" id="as-d">${drivers.map((d) => `<option value="${d.id}">${esc(d.name)} — ${d.kind === 'npc' ? 'NPC' : 'Player'}, skill ${d.skill}${d.onDuty ? ', on duty' : ''}</option>`).join('')}</select></div>
    <div class="field"><label>Truck</label><select class="input" id="as-t">${trucks.map((t) => `<option value="${t.id}">${esc((S.cfg.trucks[t.model] || {}).label || t.model)} [${esc(t.plate)}] — ${t.health}%</option>`).join('')}</select></div>
    <div class="actions"><button class="btn ghost" id="m-no">Cancel</button><button class="btn primary" id="m-yes">Assign</button></div></div>`;
  m.classList.remove('hidden');
  const done = () => { m.classList.add('hidden'); m.innerHTML = ''; };
  $('#m-no').onclick = done;
  $('#m-yes').onclick = async () => { const d = Number($('#as-d').value); const t = Number($('#as-t').value); done(); await run('assignContract', c.id, d, t); };
}

/* ----- Staff ----- */
const EMP_STATUS = { idle: ['Available', 'green'], training: ['Training', 'blue'], assigned: ['Assigned', 'yellow'], on_job: ['On the road', 'accent'] };
VIEWS.employees = async () => {
  const res = await call('getEmployees');
  if (!res.ok) return fail(res);
  const list = arr(res.data.list);
  let h = head('Staff', `${list.length} of ${res.data.max} positions filled`, can('hire') ? `<button class="btn primary" ${act(() => go('hire'))}><i class="fa-solid fa-user-plus"></i>Hire</button>` : '');
  if (!list.length) return h + empty('users', 'No staff yet. Head to Hiring.');
  const sel = list.find((e) => e.id === S.sel.emp) || list[0];
  S.sel.emp = sel.id;
  h += `<div class="split"><div class="list">`;
  list.forEach((e) => {
    const role = S.cfg.roles[e.role] || { label: e.role, icon: 'user' };
    const [st, col] = EMP_STATUS[e.status] || [e.status, ''];
    const who = e.kind === 'player' ? (e.online ? (e.onDuty ? 'Player • on duty' : 'Player • off duty') : 'Player • offline') : 'NPC';
    h += `<div class="item click ${e.id === sel.id ? 'sel' : ''}" ${act(() => { S.sel.emp = e.id; render(); })}>
      <div class="ic ${e.kind === 'player' ? 'blue' : ''}"><i class="fa-solid fa-${role.icon}"></i></div>
      <div class="main"><div class="t">${esc(e.name)}</div><div class="d">${role.label} • ${who} • skill ${e.skill}</div></div>
      <div class="end"><span class="chip ${col}">${st}${e.status === 'training' && e.trainingLeft ? ' ' + count(e.trainingLeft, 'done') : ''}</span></div></div>`;
  });
  h += `</div><div class="card">`;
  const e = sel;
  const role = S.cfg.roles[e.role] || { label: e.role, minWage: 0, maxWage: 0 };
  const certs = obj(e.certs);
  h += `<h3>${esc(e.name)} <span class="chip ${e.kind === 'player' ? 'blue' : ''}">${e.kind === 'player' ? 'Player' : 'NPC'}</span></h3>
    <div class="kv"><div class="k">Role</div><div class="v">${role.label}</div>
    <div class="k">Skill</div><div class="v">${e.skill}/100</div>
    <div class="k">Wage</div><div class="v">${money(e.wage)} / shift</div>
    <div class="k">Loads done</div><div class="v">${e.jobs_done}</div>
    <div class="k">Certifications</div><div class="v">${esc(certNames(certsOf(certs)))}</div></div>
    <div class="bar mt12"><div style="width:${e.skill}%"></div></div>`;
  const idle = e.status === 'idle';
  if (can('train')) {
    const courses = Object.entries(S.cfg.certifications).filter(([k, c]) => !certs[k] && (!c.roles || c.roles[e.role]));
    h += `<h3 class="mt16">Training</h3>`;
    if (!courses.length) h += `<div class="muted small">No courses left for this role.</div>`;
    else h += `<div class="list">${courses.map(([k, c]) => {
      const locked = c.requires && !certs[c.requires];
      return `<div class="item" style="padding:9px 12px"><div class="main"><div class="t">${esc(c.label)}</div><div class="d">${locked ? 'Requires ' + esc(S.cfg.certifications[c.requires].label) : `${money(c.cost)} • ${c.minutes} min`}</div></div>
        <button class="btn sm" ${locked || !idle ? 'disabled' : ''} ${act(async () => { if (await confirmBox('Enroll', `Send <b>${esc(e.name)}</b> to <b>${esc(c.label)}</b> for <b>${money(c.cost)}</b>?`)) run('trainEmployee', e.id, k); })}>Enroll</button></div>`;
    }).join('')}</div>`;
  }
  if (can('hire')) {
    const roles = Object.entries(S.cfg.roles).filter(([, r]) => e.kind === 'player' || r.npc);
    h += `<h3 class="mt16">Role & wage</h3><div class="row"><select class="input" id="emp-role" ${idle ? '' : 'disabled'}>${roles.map(([k, r]) => `<option value="${k}" ${k === e.role ? 'selected' : ''}>${r.label}</option>`).join('')}</select>
      <button class="btn sm" ${idle ? '' : 'disabled'} ${act(() => { const r = $('#emp-role').value; if (r !== e.role) run('setRole', e.id, r); })}>Save</button></div>
      <div class="row mt8"><div class="money-input" style="flex:1"><span>${esc(S.cfg.currency)}</span><input class="input" id="emp-wage" type="number" value="${e.wage}" min="${role.minWage}" max="${role.maxWage}"></div>
      <button class="btn sm" ${act(() => run('setWage', e.id, Number($('#emp-wage').value)))}>Set wage</button></div>
      <div class="muted small mt8">Range ${money(role.minWage)} – ${money(role.maxWage)} per shift</div>`;
  }
  if (can('fire')) h += `<button class="btn danger block mt16" ${act(async () => { if (await confirmBox('Fire employee', `Let <b>${esc(e.name)}</b> go?`, 'Fire', true)) { S.sel.emp = null; run('fireEmployee', e.id); } })}><i class="fa-solid fa-user-xmark"></i>Fire</button>`;
  h += `</div></div>`;
  return h;
};

/* ----- Hiring ----- */
VIEWS.hire = async () => {
  const res = await call('getCandidates');
  if (!res.ok) return fail(res);
  const d = res.data;
  const list = arr(d.list);
  let h = head('Hiring', `NPC applicants refresh in ${count(d.refreshIn, 'now')} • recruiter fee ${money(d.fee)} per hire`);
  h += `<div class="grid g3">`;
  list.forEach((c, i) => {
    const role = S.cfg.roles[c.role];
    h += `<div class="card"><div class="row between"><div class="row"><div class="item" style="padding:0;border:0;background:none"><div class="ic accent"><i class="fa-solid fa-${role.icon}"></i></div></div>
      <div><div class="bold">${esc(c.name)}</div><div class="muted small">${role.label} • ${c.years} yrs</div></div></div></div>
      <div class="kv mt12"><div class="k">Skill</div><div class="v">${c.skill}</div><div class="k">Asks</div><div class="v">${money(c.wage)}/shift</div><div class="k">Certs</div><div class="v">${esc(certNames(certsOf(c.certs)))}</div></div>
      <div class="bar mt8"><div style="width:${c.skill}%"></div></div>
      <button class="btn primary block mt12" ${act(async () => { if (await confirmBox('Hire', `Hire <b>${esc(c.name)}</b> as ${role.label}?<br><br>Recruiter fee: <b>${money(d.fee)}</b><br>Wage: <b>${money(c.wage)}</b> per shift`, 'Hire')) run('hireCandidate', i + 1); })}>Hire</button></div>`;
  });
  if (!list.length) h += `<div class="card">${empty('hourglass', 'No applicants right now.')}</div>`;
  h += `</div>`;
  const near = await post('nearbyPlayers');
  const roles = Object.entries(S.cfg.roles);
  h += `<div class="card mt16"><h3>Hire a player</h3><div class="muted small mb12">Offer a job to someone standing next to you. They get a pop-up to accept.</div>
    <div class="grid g4" style="align-items:end">
      <div class="field" style="margin:0"><label>Player nearby</label><select class="input" id="hp-p">${arr(near).length ? arr(near).map((p) => `<option value="${p.id}">${esc(p.name)}</option>`).join('') : '<option value="">Nobody nearby</option>'}</select></div>
      <div class="field" style="margin:0"><label>Role</label><select class="input" id="hp-r">${roles.map(([k, r]) => `<option value="${k}">${r.label}</option>`).join('')}</select></div>
      <div class="field" style="margin:0"><label>Wage per shift</label><div class="money-input"><span>${esc(S.cfg.currency)}</span><input class="input" id="hp-w" type="number" value="${S.cfg.roles.driver.minWage}"></div></div>
      <button class="btn primary" ${arr(near).length ? '' : 'disabled'} ${act(() => run('invitePlayer', Number($('#hp-p').value), $('#hp-r').value, Number($('#hp-w').value)))}><i class="fa-solid fa-paper-plane"></i>Send offer</button>
    </div></div>`;
  return h;
};

/* ----- Fleet ----- */
VIEWS.fleet = async () => {
  if (S.view.dealer) return dealer();
  const res = await call('getFleet');
  if (!res.ok) return fail(res);
  const list = arr(res.data.list);
  const full = list.length >= res.data.max;
  let h = head('Fleet', `${list.length} of ${res.data.max} yard spaces used`,
    can('fleet') ? `<button class="btn primary" ${full ? 'disabled' : ''} ${act(() => { S.view.dealer = true; render(); })}><i class="fa-solid fa-cart-shopping"></i>Buy a truck</button>` : '');
  if (full && can('fleet')) h += `<div class="banner yellow"><i class="fa-solid fa-warehouse"></i>Yard is full. Buy a Truck Yard Expansion in Office upgrades.</div>`;
  if (!list.length) return h + empty('truck', 'No trucks yet.');
  h += `<div class="grid g3">`;
  const ST = { available: ['In yard', 'green'], reserved: ['Reserved', 'yellow'], in_use: ['On the road', 'accent'] };
  list.forEach((t) => {
    const def = S.cfg.trucks[t.model] || { label: t.model, class: '?' };
    const [st, col] = ST[t.status] || [t.status, ''];
    const free = t.status === 'available';
    h += `<div class="card"><img class="truck-img" src="${truckImg(t.model)}" onerror="this.style.visibility='hidden'">
      <div class="row between"><div><div class="bold">${esc(def.label)}</div><div class="muted small">${esc(t.plate)} • ${def.class === 'semi' ? 'Semi' : 'Box truck'}</div></div><span class="chip ${col}">${st}</span></div>
      <div class="row between mt12 small"><span class="muted">Condition</span><span class="bold">${t.health}%</span></div>
      <div class="bar ${healthColor(t.health)} mt8"><div style="width:${t.health}%"></div></div>
      <div class="kv mt12"><div class="k">Mileage</div><div class="v">${Number(t.mileage).toFixed(1)} km</div><div class="k">Premium</div><div class="v">${money(t.premium)} / payroll</div></div>`;
    if (can('fleet')) {
      h += `<div class="field mt12" style="margin-bottom:8px"><label>Insurance</label><select class="input" ${onChange(async (el) => {
        const tier = S.cfg.insurance[el.value];
        if (await confirmBox('Change insurance', `Switch <b>${esc(t.plate)}</b> to <b>${esc(tier.label)}</b>?<br>Premium ${money(t.price * tier.premiumPct)} per payroll, covers ${Math.round(tier.coverage * 100)}% after a ${money(tier.deductible)} deductible.`)) run('setInsurance', t.id, el.value);
        else el.value = t.insurance;
      })}>${Object.entries(S.cfg.insurance).map(([k, v]) => `<option value="${k}" ${k === t.insurance ? 'selected' : ''}>${v.label}</option>`).join('')}</select></div>
      <div class="row"><button class="btn sm" style="flex:1;justify-content:center" ${free && t.repairCost > 0 ? '' : 'disabled'} ${act(() => run('repairTruck', t.id))}><i class="fa-solid fa-wrench"></i>${t.repairCost > 0 ? 'Repair ' + money(t.repairCost) : 'No repairs'}</button>
      <button class="btn sm danger" ${free ? '' : 'disabled'} ${act(async () => { if (await confirmBox('Sell truck', `Sell <b>${esc(t.plate)}</b> for <b>${money(t.price * S.cfg.fleet.sellRefund * t.health / 100)}</b>?`, 'Sell', true)) run('sellTruck', t.id); })}>Sell</button></div>`;
    }
    h += `</div>`;
  });
  return h + `</div>`;
};

function dealer() {
  const list = Object.entries(S.cfg.trucks).sort((a, b) => a[1].price - b[1].price);
  let h = head('Truck dealer', 'Bought with company funds and parked in your yard.', `<button class="btn ghost" ${act(() => { S.view.dealer = false; render(); })}><i class="fa-solid fa-arrow-left"></i>Back to fleet</button>`);
  h += `<div class="grid g3">`;
  list.forEach(([model, def]) => {
    h += `<div class="card"><img class="truck-img" src="${truckImg(model)}" onerror="this.style.visibility='hidden'">
      <div class="row between"><div class="bold">${esc(def.label)}</div><span class="chip ${def.class === 'semi' ? 'blue' : 'accent'}">${def.class === 'semi' ? 'Semi' : 'Box truck'}</span></div>
      <div class="muted small mt8">${def.class === 'semi' ? 'Pulls trailers: freight, fuel, timber, machinery. Drivers need a CDL.' : 'Local freight like parcels and furniture. No CDL needed.'}</div>
      <div class="row between mt12"><div style="font-size:20px;font-weight:800">${money(def.price)}</div>
      <button class="btn primary" ${act(async () => { if (await confirmBox('Buy truck', `Buy a <b>${esc(def.label)}</b> for <b>${money(def.price)}</b> from the company account?`, 'Buy')) { const r = await run('buyTruck', model); if (r.ok) { S.view.dealer = false; render(); } } })}>Buy</button></div></div>`;
  });
  return h + `</div>`;
}

/* ----- Office upgrades ----- */
VIEWS.upgrades = async () => {
  const d = S.dash;
  const ups = obj(d.upgrades);
  let h = head('Office upgrades', 'Your office starts as a bare shell. Each upgrade adds furniture and raises a company limit.',
    S.inOffice ? `<button class="btn primary" ${act(() => post('arrange'))}><i class="fa-solid fa-couch"></i>Arrange furniture</button>` : '');
  h += `<div class="grid g2">`;
  Object.entries(S.cfg.upgrades).sort((a, b) => a[1].label.localeCompare(b[1].label)).forEach(([key, up]) => {
    const lvl = ups[key] || 0;
    const levels = arr(up.levels);
    const next = levels[lvl];
    h += `<div class="card"><div class="row"><div class="item" style="padding:0;border:0;background:none"><div class="ic accent"><i class="fa-solid fa-${up.icon}"></i></div></div>
      <div style="flex:1"><div class="bold">${esc(up.label)}</div><div class="muted small">${esc(up.description)}</div></div></div>
      <div class="row between mt12"><div class="pips">${levels.map((_, i) => `<span class="${i < lvl ? 'on' : ''}"></span>`).join('')}</div><span class="muted small">Level ${lvl}/${levels.length}</span></div>
      <button class="btn ${next ? 'primary' : ''} block mt12" ${next ? '' : 'disabled'} ${act(async () => { if (await confirmBox('Upgrade', `Buy <b>${esc(up.label)}</b> level ${lvl + 1} for <b>${money(next.price)}</b>?`, 'Buy')) run('buyUpgrade', key); })}>${next ? 'Upgrade • ' + money(next.price) : 'Maxed out'}</button></div>`;
  });
  return h + `</div>`;
};

/* ----- Dispatch automation ----- */
VIEWS.dispatch = async () => {
  const d = S.dash;
  const s = Object.assign({}, d.settings);
  const c = d.counts || {};
  const sw = (key, title, desc) => `<div class="toggle"><div><div class="tt">${title}</div><div class="td">${desc}</div></div><div class="switch ${s[key] ? 'on' : ''}" ${act((el) => { s[key] = !s[key]; el.classList.toggle('on', s[key]); })}></div></div>`;
  let h = head('Dispatch automation', 'Certified NPC dispatchers run the company while you are busy.');
  if (!c.dispatchers) h += `<div class="banner yellow"><i class="fa-solid fa-headset"></i>You have no dispatchers. Hire one and get them Dispatch Certification to automate.</div>`;
  h += `<div class="split"><div class="card">
    ${sw('autoBid', 'Bid on loads automatically', 'Dispatchers bid on loads your idle drivers and trucks can actually cover. Skilled dispatchers price closer to what wins.')}
    ${sw('autoAssign', 'Assign won loads', 'Won loads go to the best idle, qualified driver and the healthiest matching truck.')}
    ${sw('usePlayerDrivers', 'Include player drivers', 'Allow dispatch to send loads to clocked-in player drivers (after NPC drivers).')}
    <button class="btn primary block mt16" ${act(() => run('saveSettings', s))}><i class="fa-solid fa-floppy-disk"></i>Save settings</button></div>
    <div class="card"><h3>How capacity works</h3><div class="muted" style="line-height:1.6">Each certified dispatcher juggles a few loads at once. Skill adds more, and the <b>Dispatch Center</b> upgrade adds one per dispatcher per level. Uncertified dispatchers and dispatchers in training don't automate anything.</div>
    <div class="kv mt16"><div class="k">Dispatchers</div><div class="v">${c.dispatchers || 0}</div><div class="k">Drivers</div><div class="v">${c.drivers || 0}</div><div class="k">Trucks</div><div class="v">${c.trucks || 0}</div><div class="k">Active loads</div><div class="v">${c.active || 0}</div></div></div></div>`;
  return h;
};

/* ----- My shift (player employees) ----- */
VIEWS.driver = async () => {
  const res = await call('getMyAssignments');
  if (!res.ok) return fail(res);
  const d = res.data;
  const list = arr(d.list);
  let h = head('My shift', 'Clock in to receive loads from dispatch. Wages only pay out for shifts you clocked in.');
  h += `<div class="grid g2"><div class="card"><div class="row between"><div><div class="bold" style="font-size:18px">${d.onDuty ? 'On duty' : 'Off duty'}</div><div class="muted small">${d.onDuty ? 'Dispatch can send you loads.' : 'You will not receive loads.'}</div></div>
      <button class="btn ${d.onDuty ? 'danger' : 'green'}" ${act(() => run('toggleDuty'))}><i class="fa-solid fa-clock"></i>${d.onDuty ? 'Clock out' : 'Clock in'}</button></div></div>
    <div class="card"><div class="row between"><div><div class="muted small">Paycheck waiting</div><div class="bold" style="font-size:22px">${money(d.pending)}</div></div>
      <button class="btn primary" ${d.pending > 0 ? '' : 'disabled'} ${act(() => run('collectPay'))}><i class="fa-solid fa-money-check-dollar"></i>Collect</button></div></div></div>`;
  h += `<div class="card mt16"><h3>Assigned loads</h3>`;
  if (!list.length) h += empty('road', 'Nothing assigned to you right now.');
  else h += `<div class="list">${list.map((c) => `<div class="item"><div class="ic accent"><i class="fa-solid fa-${c.class === 'semi' ? 'trailer' : 'box'}"></i></div>
      <div class="main"><div class="t">#${c.id} ${esc(c.cargoLabel)} → ${esc(c.dropoff.label)}</div><div class="d">Truck ${esc(c.truck_plate || '?')} • ${c.distance.toFixed(1)} km • due ${count(c.deadlineIn || 0, 'LATE')}</div></div>
      ${c.active || c.status !== 'assigned' ? '<span class="chip accent">In progress</span>' : `<button class="btn primary" ${act(() => post('startRun', { id: c.id }))}><i class="fa-solid fa-play"></i>Start load</button>`}</div>`).join('')}</div>
      <div class="muted small mt12"><i class="fa-solid fa-circle-info"></i> Your truck is pulled out at the company yard. Go outside before starting.</div>`;
  h += `</div><button class="btn danger mt16" ${act(async () => { if (await confirmBox('Leave the company', 'Quit your job? Any waiting paycheck is paid out.', 'Quit', true)) { const r = await call('quitCompany'); toast(r.msg, r.ok); if (r.ok) post('companyGone'); } })}><i class="fa-solid fa-door-open"></i>Leave the company</button>`;
  return h;
};

/* ----- Owner ----- */
VIEWS.owner = async () => {
  const d = S.dash;
  let h = head('Owner', 'Company-level controls only you can use.');
  h += `<div class="grid g2"><div class="card"><h3>Drive for your company</h3><div class="muted small mb12">Join your own roster as an unpaid driver so you can run loads yourself.</div>
      <button class="btn ${d.onRoster ? '' : 'primary'}" ${d.onRoster ? 'disabled' : ''} ${act(() => run('joinRoster'))}><i class="fa-solid fa-id-card"></i>${d.onRoster ? 'You are on the roster' : 'Join roster'}</button></div>
    <div class="card"><h3>Rename company</h3><div class="row"><input class="input" id="rn" value="${esc(d.name)}" maxlength="40">
      <button class="btn" ${act(() => run('renameCompany', $('#rn').value))}>Save</button></div></div></div>
    <div class="card mt16" style="border-color:#4a2222"><h3 style="color:var(--red)">Danger zone</h3>
      <div class="muted small mb12">Selling deletes the company, all staff and trucks. You get ${Math.round(S.cfg.propertyRefund * 100)}% of the property price, trucks at resale value and the remaining balance.</div>
      <button class="btn danger" ${act(async () => { if (await confirmBox('Sell company', `This <b>permanently deletes</b> ${esc(d.name)}, its employees and trucks. Are you sure?`, 'Sell company', true)) { const r = await call('sellCompany'); toast(r.msg, r.ok); if (r.ok) post('companyGone'); } })}><i class="fa-solid fa-skull"></i>Sell company</button></div>`;
  return h;
};

/* ----- Property listing (buy) ----- */
VIEWS.listing = async () => {
  const id = S.extra && S.extra.propertyId;
  const p = S.cfg.properties[id];
  if (!p) return empty('building', 'Unknown property.');
  $('#sb-company').textContent = 'Los Santos Commercial Realty';
  let h = `<div class="hero"><div class="chip accent"><i class="fa-solid fa-sign-hanging"></i>For sale</div><h2 class="mt12">${esc(p.label)}</h2><div class="price">${money(p.price)}</div>
    <div class="muted mt8">Commercial depot with office space and a truck yard, down by the docks.</div></div>
    <div class="grid g4">
      <div class="card stat"><div class="k">Upkeep</div><div class="v" style="font-size:20px">${money(p.upkeep)}</div><div class="s">every ${S.cfg.payrollMinutes} min</div></div>
      <div class="card stat"><div class="k">Office</div><div class="v" style="font-size:20px">${esc(p.interior)}</div><div class="s">bare shell, upgradeable</div></div>
      <div class="card stat"><div class="k">Staff</div><div class="v" style="font-size:20px">${S.cfg.base.maxEmployees}</div><div class="s">to start</div></div>
      <div class="card stat"><div class="k">Trucks</div><div class="v" style="font-size:20px">${S.cfg.base.maxTrucks}</div><div class="s">to start</div></div>
    </div>
    <div class="card mt16"><h3>Found your trucking company</h3><div class="row"><input class="input" id="cn" placeholder="Rourke Freight Lines" maxlength="40">
      <button class="btn primary" ${act(async () => {
        const name = $('#cn').value.trim();
        if (name.length < 3) return toast('Company name must be at least 3 characters.', false);
        if (await confirmBox('Confirm purchase', `Buy <b>${esc(p.label)}</b> for <b>${money(p.price)}</b> from your bank and found <b>${esc(name)}</b>?`, 'Buy')) {
          const r = await call('buyProperty', id, name); toast(r.msg, r.ok);
        }
      })}><i class="fa-solid fa-file-signature"></i>Buy for ${money(p.price)}</button></div>
      <div class="muted small mt8">Paid from your personal bank. After that, everything runs on the company's own account.</div></div>
    <div class="row mt16"><button class="btn ghost" ${act(close)}>Close</button></div>`;
  return h;
};

/* ---------------- lifecycle ---------------- */
function scaleTablet() {
  const s = Math.min(window.innerWidth / 1240, window.innerHeight / 780) * 0.88;
  document.documentElement.style.setProperty('--s', s);
  $('#tablet').style.transform = `scale(${s})`;
}
window.addEventListener('resize', scaleTablet);

async function open(msg) {
  S.cfg = msg.config;
  S.app = msg.app || 'home';
  S.extra = msg.extra || null;
  S.inOffice = !!msg.inOffice;
  S.sel = {};
  S.view = {};
  $('#root').classList.remove('hidden');
  post('opened');
  scaleTablet();
  tickClock();
  $('#content').innerHTML = '<div class="spin"><i class="fa-solid fa-circle-notch fa-spin"></i></div>';
  await render();
}

window.addEventListener('message', (e) => {
  const msg = e.data || {};
  if (msg.action === 'open') open(msg);
  if (msg.action === 'close') { $('#root').classList.add('hidden'); $('#modal').classList.add('hidden'); }
});
document.addEventListener('keyup', (e) => {
  if (e.key !== 'Escape') return;
  if (!$('#modal').classList.contains('hidden')) { $('#modal').classList.add('hidden'); $('#modal').innerHTML = ''; return; }
  close();
});
$('#homebtn').addEventListener('click', close);

// browser preview / screenshot mode
if (window.TC_MOCK) window.TC_MOCK.ready(open);
else post('ready');
