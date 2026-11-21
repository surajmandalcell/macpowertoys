// Live replica of the Portman menu-bar panel (Dark), built from PortmanPanelView, PortmanOverviewParts,
// PortmanForwardParts, and the OnePlusUI Fill steps tokens. All data is made up.
// API: window.PortmanDemo.mount(hostEl) -> { step(i), steps: 5 }
(() => {
const BASE = new URL('assets/portman/', document.currentScript ? document.currentScript.src : location.href).href;
const W = 356, RAM_MB = 24576;
const SERIES = ['#6EC7ED', '#B599F0', '#EB9CD4', '#7D9CF2', '#7DDCE0'];
// Demo-only warning (not in the app): a server past 600 MB turns OnePlusColor.danger on a dangerFill tint.
const HOT_MB = 600, DANGER = '#FFB6AC', DANGER_FILL = '#382624';
const portColor =p => SERIES[Math.floor(p * 7 / 11) % 5];
const hexA = (hex, a) => hex + Math.round(a * 255).toString(16).padStart(2, '0');
// OnePlusLinearBadge: the port in its color on a sunken well.
const chip = p => `<span class="chip" style="color:${portColor(p)}"><span class="edge"></span>:${p}</span>`;

// SF Symbols rendered from AppKit at their app point size (white masks), sized in points.
const GLYPHS = {
  'bell-13': [14, 16], 'gearshape-13': [16, 16], 'arrow-up-right-11': [10, 10], 'arrow-left-arrow-right-13': [17, 17],
  'terminal-8': [12, 10], 'arrow-triangle-branch-9': [11, 11], 'chevron-up-chevron-down-9': [9, 12],
  'chevron-right-9': [8, 10], 'link-13': [17, 17], 'arrow-up-right-square-13': [16, 14], 'stop-circle-13': [15, 15],
  'checkmark-12': [13, 13], 'chevron-right-11': [9, 12],
  'network-10': [12, 12], 'cpu-10': [12, 12], 'memorychip-10': [13, 11], 'internaldrive-10': [14, 11],
};
const g = (name, color) => {
  const [w, h] = GLYPHS[name];
  return `<i class="g" style="width:${w}px;height:${h}px;-webkit-mask-image:url(${BASE}${name}.png);mask-image:url(${BASE}${name}.png)${color ? ';color:' + color : ''}"></i>`;
};
const PORTMAN_GLYPH = 'data:image/svg+xml,' + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32"><path d="M4.5 5.5h23v15.5h-4.5v3h-4v3h-6v-3h-4v-3H4.5z" fill="none" stroke="#fff" stroke-width="2.5" stroke-linejoin="round"/><path d="M9 10v5.5m3.5-5.5v5.5M16 10v5.5m3.5-5.5v5.5M23 10v5.5" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round"/></svg>');

const CSS = `
:host{display:block;contain:layout}
*{box-sizing:border-box;margin:0}
.wrap{position:relative;width:${W}px;transform-origin:0 0}
.stage{position:relative;width:${W}px;font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text",Inter,"Helvetica Neue",sans-serif;
  color:#EDEDEF;font-size:13px;letter-spacing:-.08px;font-variant-numeric:tabular-nums;-webkit-font-smoothing:antialiased;
  user-select:none;-webkit-user-select:none;cursor:default}
.g{display:inline-block;flex:none;background:currentColor;-webkit-mask-size:100% 100%;mask-size:100% 100%;-webkit-mask-repeat:no-repeat;mask-repeat:no-repeat}
.panel{position:absolute;left:0;top:0;width:${W}px;background:#151517;border-radius:12px;overflow:hidden;
  box-shadow:0 0 0 .5px rgba(0,0,0,.85),inset 0 0 0 .5px rgba(255,255,255,.1),0 18px 44px rgba(0,0,0,.5),0 2px 8px rgba(0,0,0,.35)}
.bar{height:46px;padding:0 10px;display:flex;align-items:center;gap:8px}
.bar .sp{flex:1}
.trail{display:flex;align-items:center;gap:2px}
.edge{position:absolute;inset:0;border-radius:inherit;padding:1px;pointer-events:none;
  -webkit-mask:linear-gradient(#000 0 0) content-box exclude,linear-gradient(#000 0 0);mask:linear-gradient(#000 0 0) content-box exclude,linear-gradient(#000 0 0)}
.track{position:relative;display:flex;gap:2px;padding:2px;border-radius:8px;background:linear-gradient(#050506,#09090A);box-shadow:inset 0 1.5px 2.5px rgba(0,0,0,.9)}
.track>.edge{background:linear-gradient(rgba(0,0,0,.7),rgba(255,255,255,.12))}
.key{position:relative;width:26px;height:26px;border-radius:6px;display:grid;place-items:center;color:#9A9AA1}
.key.on{color:#C4C4CA;background:linear-gradient(#313136,#28282C);box-shadow:0 1px 3px rgba(0,0,0,.55)}
.key.on>.edge{background:linear-gradient(rgba(255,255,255,.08),rgba(255,255,255,0))}
.key .pg{width:17.5px;height:17.5px;background:currentColor;-webkit-mask:url("${PORTMAN_GLYPH}") center/100% 100% no-repeat;mask:url("${PORTMAN_GLYPH}") center/100% 100% no-repeat}
.ib{position:relative;width:28px;height:28px;border-radius:6px;display:grid;place-items:center;color:#B4B4BA}
.trail .ib{width:26px;height:26px}
.trail .open .g{transform:translate(-.5px,.5px)}
.ib.press{background:rgba(255,255,255,.06)}
.spin{width:13px;height:13px;animation:spin 1s steps(8) infinite}
@keyframes spin{to{transform:rotate(360deg)}}
.body{padding:2px 10px 12px;display:flex;flex-direction:column;gap:10px}
.grp{background:#1F1F22;border-radius:10px;padding:4px 0}
.hero{padding:16px 0;display:flex;flex-direction:column;align-items:center;gap:20px}
.ring{position:relative;width:132px;height:132px}
.ring svg{position:absolute;inset:0;overflow:visible}
.ring .c{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:1px}
.ring .t{display:flex;align-items:baseline;gap:3px}
.ring .n{font-size:26px;font-weight:300;letter-spacing:0;color:#EDEDEF;line-height:31px}
.ring .u{font-size:13px;color:#B4B4BA}
.cap{font-size:11px;letter-spacing:0;color:#9999A1;line-height:13px}
.stats{display:flex;width:100%;padding:0 10px;align-items:center}
.stat{flex:1;display:flex;flex-direction:column;align-items:center;gap:2px}
.stat b{font-size:15px;font-weight:500;letter-spacing:0;line-height:18px}
.sdiv{width:1px;height:30px;background:linear-gradient(transparent,rgba(255,255,255,.075),transparent)}
.rows{position:relative}
.row{position:relative;height:40px;padding:0 10px;display:flex;align-items:center;gap:8px;overflow:hidden}
.row::before,.pick::before{content:"";position:absolute;inset:1px 4px;border-radius:6px;background:#2A2A2E;opacity:0;transition:opacity .2s}
.row.hov::before,.pick.hov::before{opacity:1;transition-duration:.09s}
.row>*{position:relative;z-index:1}
.chipc{width:50px;flex:none}
.chip{position:relative;display:inline-flex;align-items:center;height:18px;padding:0 5px;border-radius:5px;font-size:11px;font-weight:600;letter-spacing:0;
  background:linear-gradient(#111113,#161618);box-shadow:inset 0 .75px 2px rgba(0,0,0,.6)}
.chip>.edge,.well>.edge{background:linear-gradient(rgba(0,0,0,.7),rgba(255,255,255,.12))}
.ico{width:16px;height:16px;flex:none;border-radius:4px;box-shadow:inset 0 0 0 1px rgba(255,255,255,.1);display:grid;place-items:center;color:#B4B4BA}
.ico .g{transform:scale(.62)}
.nm{display:flex;flex-direction:column;gap:1px;min-width:0;overflow:hidden}
.nm b{font-size:12px;font-weight:400;letter-spacing:0;line-height:15px;white-space:nowrap}
.nm i{font-style:normal;font-size:11px;letter-spacing:0;color:#9999A1;display:flex;align-items:center;gap:4px;white-space:nowrap;line-height:13px}
.nm i .g{transform:scale(.8)}
.fl{flex:1}
.spark{width:32px;height:14px;flex:none;overflow:visible}
.acts{display:none;gap:0}
.row.hov .acts{display:flex}.row.hov .spark{display:none}
.acts .ib{width:22px;height:22px}
.mem{width:52px;flex:none;text-align:right;font-size:12px;letter-spacing:0;color:#B4B4BA;white-space:nowrap;transition:color .4s}
.row::after{content:"";position:absolute;inset:1px 4px;border-radius:6px;background:${DANGER_FILL};opacity:0;transition:opacity .4s}
.row.hot::after{opacity:1}.row.hot .mem{color:${DANGER}}
.frow{min-height:40px;padding:0 10px;display:flex;align-items:center;gap:8px}
.well{position:relative;height:28px;border-radius:7px;background:linear-gradient(#050506,#09090A);box-shadow:inset 0 1.5px 2.5px rgba(0,0,0,.9);
  padding:0 9px;display:flex;align-items:center;gap:8px;white-space:nowrap;min-width:0}
.well>span:not(.edge){flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis}
.field{flex:1}
.field.ph{color:#8E8E95}
.sel{width:76px;flex:none}
.sel.wide{flex:1;width:auto}
.sel.lit::after{content:"";position:absolute;inset:0;border-radius:7px;background:rgba(255,255,255,.04)}
.btn{position:relative;width:88px;height:28px;border-radius:7px;flex:none;display:grid;place-items:center;font-weight:500;background:linear-gradient(#313136,#28282C)}
.btn.off{opacity:.38}
.btn.press::after{content:"";position:absolute;inset:0;border-radius:7px;background:rgba(255,255,255,.06)}
.card{position:relative;overflow:hidden}
.hrow{position:relative;height:40px;padding:0 10px;display:flex;align-items:center;gap:8px}
.hico{position:relative;width:16px;height:16px;flex:none;border-radius:4px;box-shadow:inset 0 0 0 1px rgba(255,255,255,.1);display:grid;place-items:center;color:#B4B4BA}
.hico .dot{position:absolute;right:-4.5px;bottom:-4.5px;width:10px;height:10px;border-radius:50%;background:#1F1F22;display:grid;place-items:center}
.hico .dot::after{content:"";width:7px;height:7px;border-radius:50%;background:var(--c);transition:background .3s}
.hrow .nm b{font-weight:600}
.hrow .nm i{color:#B4B4BA}
.chev{width:12px;flex:none;display:grid;place-items:center;color:#66666E;transition:transform .25s}
.chev.open{transform:rotate(90deg)}
.tree::after,.statsw::before,.crow::before,.crow::after{content:"";position:absolute;left:17.5px;width:1px;background:rgba(255,255,255,.12)}
.tree::after{top:29px;bottom:0}
.statsw{position:relative;overflow:hidden}
.statsw::before{top:0;bottom:0}
.tiles{display:grid;grid-template-columns:1fr 1fr;gap:6px;padding:2px 10px 6px 34px}
.tile{position:relative;height:66px;border-radius:8px;background:#27272B;overflow:hidden;padding:7px 8px 0;display:flex;flex-direction:column;gap:2px}
.tile .th{position:relative;display:flex;align-items:center;gap:4px;font-size:11px;letter-spacing:0;line-height:13px;color:#B4B4BA;white-space:nowrap}
.tile .th .fl{min-width:4px}
.tile .th em{font-style:normal;color:#9999A1}
.tile .tv{position:relative;display:flex;align-items:baseline;gap:2px;white-space:nowrap}
.tile .tv b{font-size:16px;font-weight:600;letter-spacing:0;line-height:19px}
.tile .tv span{font-size:11px;letter-spacing:0;color:#B4B4BA}
.tile svg{position:absolute;left:0;bottom:0;width:100%;height:26px;overflow:visible;
  -webkit-mask-image:linear-gradient(90deg,transparent,#000 16px);mask-image:linear-gradient(90deg,transparent,#000 16px)}
.crow{position:relative;height:32px;padding:0 10px 0 34px;display:flex;align-items:center;gap:8px;overflow:hidden}
.crow::before{top:0;bottom:0}
.crow.last::before{bottom:15.5px}
.crow::after{top:15.5px;height:1px;width:10px}
.addr{flex:1;font-size:12px;letter-spacing:0;white-space:nowrap}
.tst{font-size:12px;letter-spacing:0;color:#B4B4BA;white-space:nowrap}
.crow .ib{width:22px;height:22px}
.menu{position:absolute;z-index:5;padding:5px;border-radius:11px;background:rgba(38,38,40,.86);
  -webkit-backdrop-filter:blur(30px) saturate(1.8);backdrop-filter:blur(30px) saturate(1.8);
  box-shadow:0 0 0 .5px rgba(0,0,0,.75),inset 0 0 0 .5px rgba(255,255,255,.16),0 14px 36px rgba(0,0,0,.5);
  color:rgba(255,255,255,.9);font-size:13px;letter-spacing:-.08px;min-width:186px}
.mi{height:24px;padding:0 9px 0 10px;border-radius:6px;display:flex;align-items:center;gap:8px;white-space:nowrap}
.mi span{flex:1}
.mi.red{color:#FF6961}
.mi.hl{background:#0A6CDB;color:#fff}
.msep{height:1px;margin:5px 10px;background:rgba(255,255,255,.11)}
.pop{position:absolute;z-index:5;padding:5px;border-radius:7px;background:#292929;box-shadow:inset 0 0 0 1px #343434,0 8px 24px rgba(0,0,0,.45);
  color:#DEDEDE;font-size:12px;letter-spacing:0}
.pi{height:28px;padding:0 9px;border-radius:4px;display:flex;align-items:center;gap:6px;white-space:nowrap}
.pi.hl{background:#343434}
.pi .ck{width:14px;display:grid;place-items:center}
.ptr{position:absolute;z-index:9;left:0;top:0;width:22px;height:30px;pointer-events:none;opacity:0;filter:drop-shadow(0 1px 1.5px rgba(0,0,0,.45))}
.ptr svg{display:block;transform-origin:4px 3px;transition:transform .09s}
.ptr.down svg{transform:scale(.86)}
.fade{position:absolute;inset:0;z-index:8;pointer-events:none}
`;

// Made-up dev servers. mem in MB, cpu in percent.
const SERVERS = {
  admin:      { port: 4200, name: 'admin',      branch: 'main',             up: '1h 07m', mem: 212.4, cpu: 3.1 },
  docs:       { port: 4321, name: 'docs',       branch: 'pricing',          up: '26m',    mem: 96.8,  cpu: 0.8 },
  storefront: { port: 5173, name: 'storefront', branch: 'cart',             up: '2h 14m', mem: 168.3, cpu: 4.6 },
  api:        { port: 8080, name: 'api',        branch: 'main',             up: '5h 02m', mem: 38.6,  cpu: 1.2 },
  web:        { port: 3000, name: 'web',        branch: 'main',             up: '1m',     mem: 781.4, cpu: 38.5 },
};
const sawtooth = (n, base, amp, seed) => Array.from({ length: n }, (_, i) => base + amp * (((i + seed) % 4) / 3) + (i % 3 === seed % 3 ? amp * .3 : 0));
const SPARK = { admin: sawtooth(16, 10, 4, 1), docs: sawtooth(16, 10, 3, 2), storefront: sawtooth(16, 10, 5, 3), api: sawtooth(16, 10, 2, 0),
  web: [2, 3, 3, 5, 6, 8, 9, 11, 12, 14, 15, 15, 16, 17, 17, 18] };
const HOSTS = ['build-box', 'gpu-lab', 'staging-eu'], MODES = ['Forward ports', 'Monitor', 'Both'];
// Made-up build-box readings for the host card (PortmanHostCardModel): caption, row CPU line, memory, and the four tiles.
const wave = (n, base, amp, f, ph = 0) => Array.from({ length: n }, (_, i) => base + amp * Math.sin(i * f + ph) + amp * .4 * Math.sin(i * f * 2.3 + ph));
const BOX = {
  caption: 'up 12 d · load 0.42', mem: '9.99 GB', spark: wave(14, 36, .3, .45),
  tiles: [
    { title: 'CPU', icon: 'cpu-10', meta: 'load 0.42', value: '37', unit: '%', text: '#8DB8EF', color: '#4C8FE6', series: wave(30, 26, 9, .55), max: 100 },
    { title: 'Memory', icon: 'memorychip-10', meta: '16 GB', value: '9.99', unit: 'GB', text: '#C97FA4', color: '#C97FA4', series: wave(30, 62, .6, .4), max: 100 },
    { title: 'Disk', icon: 'internaldrive-10', meta: '74.51 GB', value: '51', unit: '%', text: '#8890E0', color: '#8890E0', series: Array(30).fill(51), max: 100 },
    { title: 'Network', icon: 'network-10', meta: '↑ 289 KB/s', value: '1.2', unit: 'MB/s', text: '#45B8C4', color: '#45B8C4',
      series: wave(30, 1.1, .5, .6, 1).map(v => Math.max(.1, v)), up: wave(30, .3, .08, .8), max: 2.4 },
  ],
};

const four = ['admin', 'docs', 'storefront', 'api'], five = ['web', ...four];
const STATES = [
  { page: 'servers', rows: four, reserved: 4 },
  { page: 'servers', rows: five, reserved: 5 },
  { page: 'servers', rows: four, reserved: 5 },
  { page: 'forward', host: 'build-box', card: { health: 'waiting', forwards: [] } },
  { page: 'forward', host: 'build-box', card: { health: 'online', open: true, forwards: [{ port: 5432, state: 'run' }] } },
];

const fmtMB = mb => mb.toFixed(1) + ' MB';
const sum = (ids, k, over = {}) => ids.reduce((s, id) => s + (over[id]?.[k] ?? SERVERS[id][k]), 0);

function mount(host) {
  const root = host.shadowRoot || host.attachShadow({ mode: 'open' });
  root.innerHTML = `<style>${CSS}</style><div class="wrap"><div class="stage"></div></div>`;
  const wrap = root.querySelector('.wrap'), stage = root.querySelector('.stage');
  const $ = s => stage.querySelector(s), $$ = s => [...stage.querySelectorAll(s)];
  let token = 0, cur = -1, scale = 1, stageH = 0;
  const motion = () => document.documentElement.dataset.motion || 'play';
  const reduced = () => matchMedia('(prefers-reduced-motion: reduce)').matches;
  const animates = () => motion() === 'play' && !reduced();

  // ---------- rendering (pure: state -> DOM) ----------
  function barHTML(page, busy) {
    return `<div class="bar">
      <div class="track"><span class="edge"></span>
        <div class="key${page === 'servers' ? ' on' : ''}" data-k="servers">${page === 'servers' ? '<span class="edge"></span>' : ''}<span class="pg"></span></div>
        <div class="key${page === 'forward' ? ' on' : ''}" data-k="forward">${page === 'forward' ? '<span class="edge"></span>' : ''}${g('arrow-left-arrow-right-13')}</div>
      </div>
      <span class="sp"></span>
      <div class="trail">
        <div class="ib">${g('bell-13')}</div>
        <div class="track"><span class="edge"></span>
          <div class="ib" data-k="gear">${busy ? spinner() : g('gearshape-13')}</div>
          <div class="ib open">${g('arrow-up-right-11')}</div>
        </div>
      </div>
    </div>`;
  }
  const spinner = () => `<svg class="spin" viewBox="0 0 16 16">${Array.from({ length: 8 }, (_, i) =>
    `<line x1="8" y1="1.6" x2="8" y2="4.6" stroke="#B4B4BA" stroke-width="1.6" stroke-linecap="round" opacity="${(.25 + .75 * i / 7).toFixed(2)}" transform="rotate(${i * 45} 8 8)"/>`).join('')}</svg>`;

  function sparkPath(vals) {
    const lo = Math.min(...vals), hi = Math.max(lo + 1, ...vals), n = vals.length;
    return vals.map((v, i) => `${i ? 'L' : 'M'}${(i / (n - 1) * 32).toFixed(2)} ${(1 + (1 - (v - lo) / (hi - lo)) * 12).toFixed(2)}`).join('');
  }
  function rowHTML(id, over = {}) {
    const s = { ...SERVERS[id], ...over[id] }, c = portColor(s.port);
    return `<div class="row${s.mem > HOT_MB ? ' hot' : ''}" data-id="${id}">
      <span class="chipc">${chip(s.port)}</span>
      <span class="ico">${g('terminal-8')}</span>
      <span class="nm"><b>${s.name}</b><i>${g('arrow-triangle-branch-9')}<span>${s.branch}</span><span>·</span><span>up ${s.up}</span></i></span>
      <span class="fl"></span>
      <svg class="spark" viewBox="0 0 32 14"><path d="${sparkPath(over[id]?.spark ?? SPARK[id])}" fill="none" stroke="${c}" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round"/></svg>
      <span class="acts"><span class="ib">${g('arrow-up-right-square-13')}</span><span class="ib">${g('stop-circle-13')}</span></span>
      <span class="mem">${fmtMB(s.mem)}</span>
    </div>`;
  }
  function serversHTML(st, over = {}) {
    return `<div class="grp hero">
        <div class="ring"><svg viewBox="0 0 132 132"><circle cx="66" cy="66" r="66" fill="none" stroke="#2A2A2E" stroke-width="9"/><g class="arcs"></g></svg>
          <div class="c"><div class="t"><span class="n" data-v="total"></span><span class="u">MB</span></div><span class="cap" data-v="ram"></span></div></div>
        <div class="stats">
          <div class="stat"><b data-v="servers" style="color:#EDEDEF"></b><span class="cap">Servers</span></div><span class="sdiv"></span>
          <div class="stat"><b data-v="cpu" style="color:#8DB8EF"></b><span class="cap">CPU</span></div><span class="sdiv"></span>
          <div class="stat"><b data-v="longest" style="color:#EDEDEF">5h 02m</b><span class="cap">Longest up</span></div>
        </div>
      </div>
      <div class="grp"><div class="rows" style="min-height:${st.reserved * 40}px">${st.rows.map(id => rowHTML(id, over)).join('')}</div></div>`;
  }
  // PortmanForwardInputs: sunken wells with the 9 pt fieldInset, raised keys in the 88 pt column.
  const well = (cls, text, k, chev) => `<div class="well ${cls}"${k ? ` data-k="${k}"` : ''}><span class="edge"></span><span>${text}</span>${chev ? g('chevron-up-chevron-down-9', '#C1C1C7') : ''}</div>`;
  function forwardHTML(st) {
    const h = st.host || '', off = h ? '' : ' off';
    return `<div class="grp">
      <div class="frow">${well('field' + (h ? '' : ' ph'), h || 'alias or user@IP', 'field')}${well('sel', 'Hosts', 'hosts', true)}
        <div class="btn${off}" data-k="scan">Scan</div></div>
      <div class="frow">${well('field ph', 'Remote port')}<div class="btn${off}">Add port</div></div>
      <div class="frow">${well('sel wide', 'Both', 'mode', true)}<div class="btn${off}" data-k="add">Add host</div></div>
    </div>${st.card ? cardHTML(st.card) : ''}`;
  }
  // PortmanHostCard: the 40 pt host row, the 2 x 2 chart tiles when open, and 32 pt forward rows on the guide line.
  function cardHTML(c) {
    const on = c.health === 'online', kids = c.forwards || [];
    return `<div class="grp card" data-k="card">
      <div class="hrow${(on && c.open) || kids.length ? ' tree' : ''}" data-k="hrow">
        <span class="hico">${g('network-10')}<span class="dot" style="--c:${on ? '#6CCB8C' : '#66666E'}"></span></span>
        <span class="nm"><b>build-box</b><i>${on ? BOX.caption : 'Connecting'}</i></span><span class="fl"></span>
        ${on ? `<svg class="spark" viewBox="0 0 32 14"><path d="${sparkPath(BOX.spark)}" fill="none" stroke="#4C8FE6" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round"/></svg>
          <span class="mem">${BOX.mem}</span><span class="chev${c.open ? ' open' : ''}">${g('chevron-right-9')}</span>` : ''}
      </div>
      ${on && c.open ? statsHTML() : ''}${kids.map((f, i) => childHTML(f, i === kids.length - 1)).join('')}
    </div>`;
  }
  const TILE_W = (W - 34 - 10 - 6) / 2, CHART_H = 26;
  function smooth(vals, max) {
    const pts = vals.map((v, i) => [i / (vals.length - 1) * TILE_W, CHART_H - Math.max(0, Math.min(1, v / max)) * CHART_H]);
    let d = `M${pts[0][0].toFixed(2)} ${pts[0][1].toFixed(2)}`;
    for (let i = 0; i < pts.length - 1; i++) {
      const [p0, p1, p2, p3] = [pts[Math.max(0, i - 1)], pts[i], pts[i + 1], pts[Math.min(pts.length - 1, i + 2)]];
      const c1 = [p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6], c2 = [p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6];
      d += `C${[...c1, ...c2, ...p2].map(n => n.toFixed(2)).join(' ')}`;
    }
    return d;
  }
  function statsHTML() {
    return `<div class="statsw" data-k="stats"><div class="tiles">${BOX.tiles.map(t => {
      const line = smooth(t.series, t.max);
      return `<div class="tile"><div class="th">${g(t.icon)}<span>${t.title}</span><span class="fl"></span><em>${t.meta}</em></div>
        <div class="tv"><b style="color:${t.text}">${t.value}</b><span>${t.unit}</span></div>
        <svg viewBox="0 0 ${TILE_W} ${CHART_H}" preserveAspectRatio="none"><path d="${line}L${TILE_W} ${CHART_H}L0 ${CHART_H}Z" fill="${hexA(t.color, .1)}"/>
          <path d="${line}" fill="none" stroke="${t.color}" stroke-width="1.25" stroke-linecap="round" stroke-linejoin="round"/>
          ${t.up ? `<path d="${smooth(t.up, t.max)}" fill="none" stroke="#D9925A" stroke-width="1.25" stroke-linecap="round" stroke-linejoin="round"/>` : ''}</svg></div>`;
    }).join('')}</div></div>`;
  }
  function childHTML(f, last) {
    const run = f.state === 'run';
    return `<div class="crow${last ? ' last' : ''}" data-k="crow"><span class="chipc">${chip(f.port)}</span>
      <span class="addr">localhost:${f.port}</span><span class="tst">${run ? 'Forwarding' : 'Connecting'}</span>
      <span class="ib">${run ? g('link-13') : spinner()}</span></div>`;
  }
  const POINTER = `<svg width="22" height="30" viewBox="0 0 22 30"><path d="M4 3v19.5l4.6-4.4 3.1 7.2 3.3-1.4-3.1-7.1h6.5z" fill="#000" stroke="#fff" stroke-width="1.5" stroke-linejoin="round"/></svg>`;

  function render(st, opts = {}) {
    stage.innerHTML = `<div class="panel">${barHTML(st.page, opts.busy)}<div class="body">${st.page === 'servers' ? serversHTML(st, opts.over) : forwardHTML(st)}</div></div><div class="ptr">${POINTER}</div>`;
    if (st.page === 'servers') setRing(st.rows, opts.over, opts.reveal ?? 1);
  }
  function setRing(ids, over = {}, reveal = 1) {
    const segs = ids.map(id => ({ port: SERVERS[id].port, mem: over[id]?.mem ?? SERVERS[id].mem })).sort((a, b) => a.port - b.port);
    const total = segs.reduce((s, x) => s + x.mem, 0), gap = 13 / (Math.PI * 132);
    let start = 0, arcs = '';
    for (const s of segs) {
      const span = s.mem / total;
      if (span > gap) {
        const from = (start + gap / 2) * reveal, to = (start + span - gap / 2) * reveal;
        arcs += `<circle cx="66" cy="66" r="66" fill="none" stroke="${s.mem > HOT_MB ? DANGER : portColor(s.port)}" stroke-width="9" stroke-linecap="round" pathLength="1"
          stroke-dasharray="${Math.max(0, to - from).toFixed(4)} 2" stroke-dashoffset="${(-from).toFixed(4)}" transform="rotate(-90 66 66)"/>`;
      }
      start += span;
    }
    const q = s => stage.querySelector(`[data-v=${s}]`);
    if (!q('total')) return;
    stage.querySelector('.arcs').innerHTML = arcs;
    q('total').textContent = (total * reveal).toFixed(1);
    q('ram').textContent = (total / RAM_MB * 100 * reveal).toFixed(1) + '% of RAM';
    q('servers').textContent = String(Math.round(ids.length * reveal));
    q('cpu').textContent = (sum(ids, 'cpu', over) * reveal).toFixed(1) + '%';
  }

  // ---------- motion helpers ----------
  const CANCEL = Symbol('cancel');
  const live = t => { if (t !== token) throw CANCEL; };
  const wait = (ms, t) => new Promise((res, rej) => setTimeout(() => (t === token ? res() : rej(CANCEL)), ms));
  const easeOut = k => 1 - Math.pow(1 - k, 3), easeIO = k => (k < .5 ? 4 * k * k * k : 1 - Math.pow(-2 * k + 2, 3) / 2);
  const tween = (ms, fn, t, ease = easeIO) => new Promise((res, rej) => {
    const t0 = performance.now();
    const f = now => {
      if (t !== token) return rej(CANCEL);
      const k = Math.min(1, (now - t0) / ms); fn(ease(k));
      k < 1 ? requestAnimationFrame(f) : res();
    };
    requestAnimationFrame(f);
  });
  const ptr = { x: 300, y: 420 };
  function pos(el, fx = .5, fy = .5) {
    const r = el.getBoundingClientRect(), s = stage.getBoundingClientRect();
    return { x: (r.left - s.left + r.width * fx) / scale, y: (r.top - s.top + r.height * fy) / scale };
  }
  const placePtr = () => { const p = $('.ptr'); if (p) p.style.transform = `translate(${ptr.x - 4}px,${ptr.y - 3}px)`; };
  async function showPtr(t, x, y) { ptr.x = x; ptr.y = y; placePtr(); await tween(200, k => { $('.ptr').style.opacity = k; }, t); }
  async function hidePtr(t) { await tween(250, k => { const p = $('.ptr'); if (p) p.style.opacity = 1 - k; }, t); }
  async function moveTo(t, target, ms = 650) {
    const a = { ...ptr };
    await tween(ms, k => { ptr.x = a.x + (target.x - a.x) * k; ptr.y = a.y + (target.y - a.y) * k; placePtr(); }, t);
  }
  async function click(t, el) {
    const p = $('.ptr'); p.classList.add('down'); el && el.classList.add('press');
    await wait(120, t); p.classList.remove('down'); el && el.classList.remove('press'); await wait(60, t);
  }
  // Open a select's pop-up (checked item `on`), move to item `pick`, click it, and close.
  async function choose(t, k, items, on, pick) {
    const sel = $(`[data-k=${k}]`);
    await moveTo(t, pos(sel, .45, .55), 550);
    sel.classList.add('lit');
    await click(t);
    const sp = pos(sel, 0, 1);
    stage.insertAdjacentHTML('beforeend', `<div class="pop" style="left:${sp.x}px;top:${sp.y + 4}px;min-width:${Math.max(120, sel.offsetWidth)}px">
      ${items.map((h, i) => `<div class="pi${i === on ? ' hl' : ''}"><span class="ck">${i === on ? g('checkmark-12', '#DEDEDE') : ''}</span><span>${h}</span></div>`).join('')}</div>`);
    const pop = $('.pop'), pis = [...pop.querySelectorAll('.pi')];
    await tween(100, k => { pop.style.opacity = k; }, t);
    await wait(250, t);
    await moveTo(t, pos(pis[pick], .4, .55), 350);
    pis.forEach(p => p.classList.toggle('hl', p === pis[pick]));
    await wait(300, t);
    await click(t);
    await tween(120, k => { pop.style.opacity = 1 - k; }, t);
    pop.remove();
  }
  // Grow a new part from zero height to its own, fading it in.
  async function grow(t, el) {
    const h = el.offsetHeight;
    el.style.height = '0px'; el.style.opacity = '0';
    await tween(300, k => { el.style.height = h * k + 'px'; el.style.opacity = Math.min(1, k * 1.6); }, t, easeOut);
    el.style.height = ''; el.style.opacity = '';
  }

  // ---------- step timelines (each starts from the previous step's end state) ----------
  const TIMELINES = [
    async t => { // first open: the ring and numbers count up
      render(STATES[0], { reveal: 0 });
      await wait(250, t);
      await tween(600, k => setRing(four, {}, k), t, easeOut);
    },
    async t => { // web on :3000 starts and its memory climbs
      render(STATES[0]);
      await wait(300, t);
      const rows = $('.rows');
      rows.style.minHeight = '200px';
      rows.insertAdjacentHTML('afterbegin', rowHTML('web', { web: { mem: 142.0, cpu: 6, spark: SPARK.web.slice(0, 3).concat(Array(13).fill(3)) } }));
      const row = $('[data-id=web]');
      row.style.height = '0px'; row.style.opacity = '0';
      setRing(five, { web: { mem: 142.0, cpu: 6 } });
      await tween(300, k => {
        const e = k * .3;
        row.style.height = 40 * easeOut(Math.min(1, e / .25)) + 'px';
        row.style.opacity = Math.max(0, Math.min(1, (e - .07) / .2));
      }, t, x => x);
      await wait(250, t);
      const memEl = row.querySelector('.mem'), path = row.querySelector('path');
      await tween(2600, k => {
        const mem = 142.0 + (781.4 - 142.0) * k, cpu = 6 + (38.5 - 6) * k;
        memEl.textContent = fmtMB(mem);
        row.classList.toggle('hot', mem > HOT_MB);
        const n = Math.max(3, Math.round(3 + 13 * k));
        path.setAttribute('d', sparkPath(SPARK.web.slice(0, n).concat(Array(16 - n).fill(SPARK.web[n - 1]))));
        setRing(five, { web: { mem, cpu } });
      }, t, x => x);
    },
    async t => { // right-click web, Stop Process Tree…, the row closes and the ring drops
      render(STATES[1]);
      await wait(200, t);
      const row = $('[data-id=web]');
      await showPtr(t, 300, 380);
      const at = pos(row.querySelector('.nm'), .55, .5);
      await moveTo(t, at, 700);
      row.classList.add('hov');
      await wait(350, t);
      await click(t);
      stage.insertAdjacentHTML('beforeend', `<div class="menu" style="left:${ptr.x}px;top:${ptr.y + 2}px">
        <div class="mi"><span>Open localhost:3000</span></div><div class="mi"><span>Show Details</span></div>
        <div class="mi red" data-k="kill"><span>Stop Process Tree…</span></div><div class="msep"></div>
        <div class="mi"><span>Sort by</span>${g('chevron-right-11')}</div><div class="mi"><span>Refresh Servers</span></div><div class="mi"><span>Clean Up…</span></div></div>`);
      const menu = $('.menu');
      await tween(120, k => { menu.style.opacity = k; }, t);
      const items = $$('.mi');
      for (const i of [0, 1, 2]) {
        await moveTo(t, pos(items[i], .35, .55), i ? 180 : 260);
        items.forEach(m => m.classList.toggle('hl', m === items[i]));
        await wait(i === 2 ? 380 : 90, t);
      }
      await click(t);
      items[2].classList.remove('hl'); await wait(70, t); items[2].classList.add('hl'); await wait(70, t);
      await tween(160, k => { menu.style.opacity = 1 - k; }, t);
      menu.remove(); row.classList.remove('hov');
      const r0 = row.offsetHeight, from = { mem: 781.4, cpu: 38.5 };
      await tween(300, k => {
        const e = k * .3;
        row.style.opacity = 1 - Math.min(1, e / .15);
        row.style.height = r0 * (1 - easeOut(Math.max(0, Math.min(1, (e - .05) / .25)))) + 'px';
      }, t, x => x);
      row.remove();
      await tween(400, k => setRing(five, { web: { mem: from.mem * (1 - k) + .001, cpu: from.cpu * (1 - k) } }), t, easeOut);
      setRing(four);
      await hidePtr(t);
    },
    async t => { // Forward: pick build-box from the SSH hosts, keep the mode on Both, Add host
      render(STATES[2]);
      await showPtr(t, 220, 300);
      await moveTo(t, pos($('[data-k=forward]')), 700);
      await click(t);
      render({ page: 'forward' }); placePtr(); $('.ptr').style.opacity = 1;
      await wait(350, t);
      await choose(t, 'hosts', ['Hosts', ...HOSTS], 0, 1);
      render({ page: 'forward', host: 'build-box' }); placePtr(); $('.ptr').style.opacity = 1;
      await wait(300, t);
      await choose(t, 'mode', MODES, 2, 2);
      $('[data-k=mode]').classList.remove('lit');
      await wait(200, t);
      const add = $('[data-k=add]');
      await moveTo(t, pos(add, .5, .55), 450);
      await click(t, add);
      render(STATES[3]); placePtr(); $('.ptr').style.opacity = 1;
      await grow(t, $('[data-k=card]'));
      await wait(300, t);
      await hidePtr(t);
    },
    async t => { // build-box answers, its charts open, and its saved forward comes up
      render(STATES[3]);
      await wait(700, t);
      const card = { health: 'online', forwards: [] };
      render({ ...STATES[4], card });
      await showPtr(t, 250, 420);
      await moveTo(t, pos($('[data-k=hrow] .nm'), .5, .5), 600);
      await click(t);
      render({ ...STATES[4], card: { ...card, open: true } }); placePtr(); $('.ptr').style.opacity = 1;
      await grow(t, $('[data-k=stats]'));
      await wait(250, t);
      render({ ...STATES[4], card: { ...card, open: true, forwards: [{ port: 5432, state: 'wait' }] } }); placePtr(); $('.ptr').style.opacity = 1;
      await grow(t, $('[data-k=crow]'));
      await wait(800, t);
      render(STATES[4]); placePtr(); $('.ptr').style.opacity = 1;
      await wait(400, t);
      await hidePtr(t);
    },
  ];

  // ---------- step control ----------
  function settle(i, crossfade) {
    let shot;
    if (crossfade && stage.firstChild) { shot = document.createElement('div'); shot.className = 'fade'; shot.innerHTML = stage.innerHTML; }
    render(STATES[i]);
    if (shot) {
      stage.append(shot);
      shot.animate([{ opacity: 1 }, { opacity: 0 }], { duration: 260, easing: 'ease-out', fill: 'forwards' }).onfinish = () => shot.remove();
    }
  }
  async function step(i) {
    i = Math.max(0, Math.min(STATES.length - 1, i | 0));
    const t = ++token, prev = cur;
    cur = i;
    if (!animates()) return settle(i, reduced() && motion() === 'play');
    if (prev !== -1 && prev !== i - 1 && !(prev === -1 && i === 0)) return settle(i, true);
    try { await TIMELINES[i](t); live(t); render(STATES[i]); }
    catch (e) { if (e !== CANCEL) throw e; }
  }

  // Fit narrow hosts: scale the stage down, never up.
  function fit() {
    const w = host.clientWidth || W;
    scale = Math.min(1, w / W);
    wrap.style.transform = scale < 1 ? `scale(${scale})` : '';
    stage.style.height = stageH + 'px';
    wrap.style.height = stageH + 'px';
    host.style.height = stageH * scale + 'px';
  }
  // Reserve the tallest step so the page never shifts when the panel grows.
  STATES.forEach(s => { render(s); stageH = Math.max(stageH, $('.panel').offsetHeight); });
  stageH += 2;
  new ResizeObserver(fit).observe(host);
  new MutationObserver(() => { if (!animates() && cur >= 0) { token++; settle(cur, false); } })
    .observe(document.documentElement, { attributes: true, attributeFilter: ['data-motion'] });
  render(STATES[0]);
  fit();
  return { step, steps: STATES.length };
}

window.PortmanDemo = { mount };
})();
