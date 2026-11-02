// ---------- seeded random so every shot has the same backdrop ----------
let seed = 7;
const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;

function background(kind) {
  const svg = document.getElementById('bg');
  seed = kind === 'road' ? 11 : kind === 'office' ? 5 : 7;
  let s = '';
  if (kind === 'office') {
    // bare warehouse office shell
    s += `<defs>
      <linearGradient id="wall" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#3a3d42"/><stop offset="1" stop-color="#25272b"/></linearGradient>
      <linearGradient id="floor" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#4a4740"/><stop offset="1" stop-color="#2a2925"/></linearGradient>
      <radialGradient id="lamp" cx=".5" cy="0" r=".8"><stop offset="0" stop-color="rgba(255,236,200,.35)"/><stop offset="1" stop-color="rgba(255,236,200,0)"/></radialGradient>
    </defs>
    <rect width="1280" height="460" fill="url(#wall)"/>
    <rect y="460" width="1280" height="260" fill="url(#floor)"/>`;
    for (let x = 0; x < 1280; x += 160) s += `<rect x="${x}" y="0" width="6" height="460" fill="#2b2d31"/>`;
    for (let x = -400; x < 1700; x += 140) s += `<line x1="640" y1="460" x2="${x}" y2="720" stroke="rgba(0,0,0,.18)" stroke-width="2"/>`;
    s += `<rect x="0" y="0" width="1280" height="720" fill="url(#lamp)"/>`;
    // shelving
    for (let i = 0; i < 3; i++) {
      const x = 80 + i * 150;
      s += `<rect x="${x}" y="230" width="120" height="235" fill="none" stroke="#1d5fa8" stroke-width="6"/>`;
      for (let y = 280; y < 465; y += 60) s += `<rect x="${x}" y="${y}" width="120" height="5" fill="#d9822b"/><rect x="${x + 10}" y="${y - 40}" width="45" height="40" fill="#a3814f"/><rect x="${x + 62}" y="${y - 32}" width="45" height="32" fill="#8f7246"/>`;
    }
    // crate + laptop + tv (base furniture)
    s += `<rect x="720" y="420" width="130" height="110" fill="#8c6b3e" stroke="#6b5130" stroke-width="4"/>
      <line x1="720" y1="420" x2="850" y2="530" stroke="#6b5130" stroke-width="4"/><line x1="850" y1="420" x2="720" y2="530" stroke="#6b5130" stroke-width="4"/>
      <polygon points="752,420 818,420 828,412 762,412" fill="#222"/><rect x="760" y="372" width="56" height="40" fill="#111" stroke="#333" stroke-width="3"/><rect x="764" y="376" width="48" height="32" fill="#1c7ed6" opacity=".7"/>
      <rect x="930" y="250" width="230" height="135" fill="#0b0b0c" stroke="#2a2a2a" stroke-width="6"/>
      <rect x="940" y="260" width="210" height="115" fill="#14304d"/>`;
    for (let i = 0; i < 5; i++) s += `<rect x="952" y="${270 + i * 21}" width="${120 + (i % 3) * 25}" height="10" fill="rgba(116,192,252,.55)"/>`;
    svg.innerHTML = s;
    return;
  }
  const road = kind === 'road';
  s += `<defs>
    <linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#1b2140"/><stop offset=".45" stop-color="#6b3b5e"/><stop offset=".75" stop-color="#e0734a"/><stop offset="1" stop-color="#f6b26b"/>
    </linearGradient>
    <linearGradient id="sea" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#5a4660"/><stop offset="1" stop-color="#1d2235"/></linearGradient>
    <linearGradient id="ground" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#3b3a40"/><stop offset="1" stop-color="#1a1a1e"/></linearGradient>
  </defs>
  <rect width="1280" height="720" fill="url(#sky)"/>
  <circle cx="${road ? 980 : 300}" cy="330" r="46" fill="#ffd8a0" opacity=".85"/>`;
  // distant city
  let x = 0;
  while (x < 1280) {
    const w = 18 + rnd() * 40, h = 30 + rnd() * (road ? 60 : 140);
    s += `<rect x="${x}" y="${420 - h}" width="${w}" height="${h}" fill="#3a2c45" opacity=".85"/>`;
    x += w + 2;
  }
  if (road) {
    // hills + highway
    s += `<path d="M0 430 Q200 360 420 410 T860 400 T1280 380 V720 H0Z" fill="#4b3a3a"/>
      <path d="M0 470 Q300 430 640 460 T1280 450 V720 H0Z" fill="#5d4a3b"/>
      <polygon points="560,470 720,470 1280,720 0,720" fill="#2d2d31"/>
      <polygon points="636,470 644,470 660,720 620,720" fill="none"/>`;
    for (let i = 0; i < 7; i++) {
      const t = i / 7, y1 = 470 + 250 * t * t, y2 = 470 + 250 * Math.pow(t + .07, 2);
      s += `<polygon points="${640 - 2 - 8 * t},${y1} ${640 + 2 + 8 * t},${y1} ${640 + 2 + 9 * (t + .07)},${y2} ${640 - 2 - 9 * (t + .07)},${y2}" fill="#e8c547"/>`;
    }
    // delivery marker
    s += `<ellipse cx="645" cy="612" rx="150" ry="30" fill="rgba(0,200,80,.35)" stroke="rgba(0,200,80,.8)" stroke-width="2"/>
      <rect x="495" y="552" width="300" height="60" fill="rgba(0,200,80,.12)"/>`;
    // truck rear + trailer
    s += `<rect x="560" y="430" width="170" height="160" fill="#c9ccd1" stroke="#8b8f96" stroke-width="3"/>
      <rect x="560" y="430" width="170" height="20" fill="#e03131"/><text x="645" y="520" font-family="Roboto" font-weight="700" font-size="22" fill="#495057" text-anchor="middle">ROURKE</text>
      <rect x="575" y="590" width="40" height="34" rx="6" fill="#111"/><rect x="675" y="590" width="40" height="34" rx="6" fill="#111"/>
      <rect x="566" y="575" width="16" height="9" fill="#ff4d4d"/><rect x="708" y="575" width="16" height="9" fill="#ff4d4d"/>`;
    svg.innerHTML = s;
    return;
  }
  // docks: sea, cranes, container stacks, asphalt
  s += `<rect y="420" width="1280" height="70" fill="url(#sea)"/>`;
  const crane = (cx, scale) => {
    const k = scale;
    return `<g transform="translate(${cx},490) scale(${k})" fill="none" stroke="#c92a2a" stroke-width="6">
      <line x1="-40" y1="0" x2="-40" y2="-260"/><line x1="40" y1="0" x2="40" y2="-260"/>
      <line x1="-40" y1="-120" x2="40" y2="-120"/><line x1="-40" y1="-200" x2="40" y2="-200"/>
      <line x1="-40" y1="-120" x2="40" y2="-200"/><line x1="40" y1="-120" x2="-40" y2="-200"/>
      <rect x="-60" y="-275" width="300" height="18" fill="#c92a2a" stroke="none"/>
      <rect x="-140" y="-275" width="80" height="18" fill="#e9ecef" stroke="none"/>
      <rect x="-20" y="-310" width="60" height="35" fill="#e9ecef" stroke="none"/>
      <line x1="160" y1="-257" x2="160" y2="-150" stroke="#222" stroke-width="2"/>
    </g>`;
  };
  s += crane(180, .9) + crane(620, 1.05) + crane(1060, .85);
  s += `<rect y="490" width="1280" height="230" fill="url(#ground)"/>`;
  const colors = ['#1971c2', '#c92a2a', '#2b8a3e', '#e67700', '#5f3dc4', '#868e96', '#0b7285'];
  for (let row = 0; row < 3; row++) {
    let cx = -30 + row * 25;
    while (cx < 1280) {
      const stack = 1 + Math.floor(rnd() * 3);
      for (let k = 0; k < stack; k++) {
        const y = 560 + row * 40 - k * 34 - row * 0;
        const c = colors[Math.floor(rnd() * colors.length)];
        s += `<rect x="${cx}" y="${y - 34}" width="92" height="34" fill="${c}" stroke="rgba(0,0,0,.35)" stroke-width="2"/>`;
        for (let r = 8; r < 92; r += 10) s += `<line x1="${cx + r}" y1="${y - 32}" x2="${cx + r}" y2="${y - 2}" stroke="rgba(0,0,0,.18)" stroke-width="2"/>`;
      }
      cx += 96 + (rnd() < .2 ? 120 : 0);
    }
  }
  s += `<rect y="640" width="1280" height="80" fill="#202024"/>`;
  for (let i = 0; i < 1280; i += 90) s += `<rect x="${i}" y="676" width="50" height="5" fill="#d9a400" opacity=".8"/>`;
  svg.innerHTML = s;
}

// ---------- UI components ----------
const esc = (t) => String(t ?? '');
const md = (t) => esc(t).replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>').replace(/\n\n/g, '</p><p>').replace(/\n/g, '<br>');
const COLORS = { green: 'var(--green)', yellow: 'var(--yellow)', red: 'var(--red)', blue: 'var(--blue)', orange: 'var(--orange)', lime: 'var(--lime)', gray: 'var(--gray)' };

function ctx(m) {
  const pos = m.pos || {};
  const style = Object.entries(pos).map(([k, v]) => `${k}:${v}`).join(';');
  let h = `<div class="ctx" style="${style}"><div class="ctx-head">`;
  if (m.back) h += `<div class="ctx-btn"><i class="fa-solid fa-chevron-left"></i></div>`;
  h += `<div class="ctx-title">${esc(m.title)}</div><div class="ctx-btn"><i class="fa-solid fa-xmark"></i></div></div><div class="ctx-list">`;
  m.options.forEach((o, i) => {
    const cls = ['opt'];
    if (o.disabled) cls.push('disabled');
    if (m.hover === i) cls.push('hover');
    const ic = o.icon ? `<div class="ico" style="${o.iconColor ? 'color:' + (COLORS[o.iconColor] || o.iconColor) : ''}"><i class="fa-solid fa-${o.icon}"></i></div>` : '';
    const bar = o.progress != null ? `<div class="bar"><div style="width:${o.progress}%;background:${COLORS[o.color || 'blue']}"></div></div>` : '';
    h += `<div class="${cls.join(' ')}" id="opt${i}">${ic}<div class="body"><div class="t">${esc(o.title)}</div>${o.desc ? `<div class="d">${esc(o.desc)}</div>` : ''}${bar}</div>${o.arrow ? '<div class="arrow"><i class="fa-solid fa-chevron-right"></i></div>' : ''}</div>`;
  });
  h += `</div></div>`;
  return h;
}

function tip(meta) {
  return `<div class="tip" id="tip">${meta.map(([k, v]) => `<div>${esc(k)}: <b>${esc(v)}</b></div>`).join('')}</div>`;
}

function notifs(list) {
  const ICON = { success: ['circle-check', 'var(--green)'], error: ['circle-xmark', 'var(--red)'], inform: ['circle-info', 'var(--blue)'], warning: ['circle-exclamation', 'var(--yellow)'] };
  return `<div class="notifs">${list.map((n) => {
    const [ic, col] = ICON[n.type || 'inform'];
    return `<div class="notif"><div class="ni" style="background:${col}"><i class="fa-solid fa-${ic}"></i></div><div><div class="nt">${esc(n.title || 'Trucking Co.')}</div><div class="nd">${esc(n.text)}</div></div></div>`;
  }).join('')}</div>`;
}

function alertBox(a) {
  return `<div class="overlay"><div class="modal"><h2>${esc(a.header)}</h2><p>${md(a.content)}</p>
    <div class="btns"><div class="btn cancel">${esc(a.cancel || 'Cancel')}</div><div class="btn ok">${esc(a.confirm || 'Confirm')}</div></div></div></div>`;
}

function inputBox(d) {
  let h = `<div class="overlay"><div class="modal input"><h2>${esc(d.title)}</h2>`;
  d.fields.forEach((f) => {
    if (f.type === 'checkbox') {
      h += `<div class="chk"><div class="box ${f.checked ? 'on' : ''}">${f.checked ? '<i class="fa-solid fa-check"></i>' : ''}</div>${esc(f.label)}</div>`;
    } else {
      const val = f.value != null ? esc(f.value) : `<span class="ph">${esc(f.placeholder || '')}</span>`;
      const right = f.type === 'select' ? '<i class="fa-solid fa-chevron-down" style="color:var(--dim);font-size:12px"></i>'
        : f.type === 'number' ? '<span style="display:flex;flex-direction:column;font-size:9px;color:var(--dim);line-height:1"><i class="fa-solid fa-chevron-up"></i><i class="fa-solid fa-chevron-down"></i></span>' : '';
      h += `<div class="field"><label>${esc(f.label)}${f.required ? ' <span class="req">*</span>' : ''}</label><div class="inp ${f.focus ? 'focus' : ''}"><span>${val}</span>${right}</div></div>`;
    }
  });
  h += `<div class="btns" style="justify-content:stretch"><div class="btn cancel" style="flex:1">Cancel</div><div class="btn ok" style="flex:1">Confirm</div></div></div></div>`;
  return h;
}

function pcircle(p) {
  const r = 34, c = 2 * Math.PI * r, off = c * (1 - p.pct / 100);
  return `<div class="pcircle"><svg width="90" height="90" viewBox="0 0 90 90">
    <circle cx="45" cy="45" r="${r}" fill="rgba(26,27,30,.85)" stroke="#373a40" stroke-width="7"/>
    <circle cx="45" cy="45" r="${r}" fill="none" stroke="#3bc9db" stroke-width="7" stroke-linecap="round" stroke-dasharray="${c}" stroke-dashoffset="${off}" transform="rotate(-90 45 45)"/>
    <text x="45" y="51" font-family="Roboto" font-size="17" font-weight="500" fill="#f1f3f5" text-anchor="middle">${p.pct}%</text></svg>
    <div class="lbl">${esc(p.label)}</div></div>`;
}

function target(t) {
  return `<div class="eye"><i class="fa-solid fa-eye"></i></div><div class="tgt">${t.options.map((o, i) =>
    `<div class="${t.hover === i ? 'hover' : ''}"><i class="fa-solid fa-${o.icon}"></i>${esc(o.label)}</div>`).join('')}</div>`;
}

function render(name) {
  const sc = SCENES[name];
  background(sc.bg || 'docks');
  let h = '';
  if (sc.target) h += target(sc.target);
  if (sc.ctx) h += ctx(sc.ctx);
  if (sc.textui) h += `<div class="textui">${esc(sc.textui)}</div>`;
  if (sc.progress) h += pcircle(sc.progress);
  if (sc.caption) h += `<div class="cap"><div class="ct">${esc(sc.caption[0])}</div><div class="cd">${esc(sc.caption[1])}</div></div>`;
  h += `<div class="brand">bdev-trucking-company</div>`;
  if (sc.alert) h += alertBox(sc.alert);
  if (sc.input) h += inputBox(sc.input);
  if (sc.notify) h += notifs(sc.notify);
  document.getElementById('ui').innerHTML = h;

  // attach metadata tooltip to the hovered option (to its left, like ox_lib)
  if (sc.ctx && sc.ctx.tip != null) {
    const el = document.getElementById('opt' + sc.ctx.hover);
    const r = el.getBoundingClientRect();
    const wrap = document.createElement('div');
    wrap.innerHTML = tip(sc.ctx.tip);
    const t = wrap.firstChild;
    document.getElementById('ui').appendChild(t);
    t.style.left = (r.left - t.offsetWidth - 10) + 'px';
    t.style.top = r.top + 'px';
  }
}

render(new URLSearchParams(location.search).get('s') || Object.keys(SCENES)[0]);
