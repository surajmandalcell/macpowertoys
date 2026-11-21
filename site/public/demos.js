// The live panel demo and the Fan page demo. Each renders in its own shadow root on a .demo host.
(() => {
const sheet = new CSSStyleSheet();
sheet.replaceSync(document.getElementById('demo-css').content.textContent);
function mount(name) {
  const host = document.querySelector('[data-demo=' + name + ']'), R = host.attachShadow({ mode: 'open' });
  R.adoptedStyleSheets = [sheet];
  R.append(host.querySelector('template').content.cloneNode(true));
  return R;
}
function engine(R) {
return (() => {
  const D = document, $ = (s, r = R) => r.querySelector(s), $$ = (s, r = R) => [...r.querySelectorAll(s)];
  const OVERLAY = new URLSearchParams(location.search).has('overlay');
  const RM = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const STILL = RM || OVERLAY;
  const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
  const lerp = (a, b, t) => a + (b - a) * t;
  let seed = 11;
  const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;

  const springs = {};
  function spring(resp = .45, damp = .825) {
    const key = resp + '/' + damp;
    if (springs[key]) return springs[key];
    const w = 2 * Math.PI / resp, a = damp * w, wd = w * Math.sqrt(1 - damp * damp);
    const f = t => 1 - Math.exp(-a * t) * (Math.cos(wd * t) + a / wd * Math.sin(wd * t));
    let T = .1;
    while (T < 4 && Math.exp(-a * T) * (1 + a / wd) > .002) T += .02;
    const p = [];
    for (let i = 0; i <= 40; i++) p.push(i === 40 ? 1 : +f(T * i / 40).toFixed(4));
    return springs[key] = { easing: `linear(${p.join(',')})`, duration: Math.round(T * 1000) };
  }

  // Virtual clock: timers and frame callbacks advance only while the demo is on screen.
  let vt = 0, last = null, on = false, started = false, paused = [];
  const timers = [], frames = new Set();
  const after = (ms, fn) => { const t = { t: vt + ms, fn }; timers.push(t); return t; };
  const every = (ms, fn, off = 0) => { const go = () => { fn(); after(ms, go); }; after(off, go); };
  const sleep = ms => new Promise(r => after(ms, r));
  function tick(ts) {
    if (!on) { last = null; return; }
    const dt = last == null ? 16 : Math.min(64, ts - last);
    last = ts; vt += dt;
    timers.sort((a, b) => a.t - b.t);
    while (timers.length && timers[0].t <= vt) timers.shift().fn();
    for (const f of frames) f(vt, dt);
    requestAnimationFrame(tick);
  }
  function run(v) {
    if (v === on || STILL) return;
    on = v;
    if (v) {
      paused.forEach(a => { try { a.play(); } catch {} });
      paused = [];
      if (!started) { started = true; enter(); api.onStart && api.onStart(); }
      requestAnimationFrame(tick);
    } else {
      paused = R.getAnimations().filter(a => a.playState === 'running');
      paused.forEach(a => a.pause());
    }
  }
  const easeIO = t => t < .5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
  function tween(ms, fn, ease = easeIO) {
    return new Promise(r => {
      const t0 = vt;
      const f = t => { const k = clamp((t - t0) / ms, 0, 1); fn(ease(k)); if (k >= 1) { frames.delete(f); r(); } };
      frames.add(f); f(vt);
    });
  }

  // Digits roll like SwiftUI .numericText: each changed character slides out and the new one springs in.
  function roll(el, text, resp = .45) {
    if (!el) return;
    const prev = el.dataset.v ?? el.textContent;
    if (prev === text) return;
    el.dataset.v = text;
    if (!on) { el.textContent = text; return; }
    const num = s => parseFloat(s.replace(/[^\d.-]/g, '')) || 0;
    const dy = num(text) >= num(prev) ? 1.1 : -1.1, sp = spring(resp);
    const n = Math.max(prev.length, text.length), a = prev.padStart(n), b = text.padStart(n);
    el.textContent = '';
    for (let i = 0; i < n; i++) {
      const c = D.createElement('span'); c.className = 'rc';
      const nw = D.createElement('span'); nw.textContent = b[i] === ' ' ? '' : b[i]; nw.style.display = 'inline-block';
      c.appendChild(nw);
      if (a[i] !== b[i]) {
        if (b[i] !== ' ') nw.animate([{ transform: `translateY(${dy}em)`, opacity: 0 }, { transform: 'none', opacity: 1 }], { ...sp, delay: i * 18, fill: 'backwards' });
        if (a[i] !== ' ') {
          const o = D.createElement('span'); o.className = 'ro'; o.textContent = a[i]; c.appendChild(o);
          o.animate([{ transform: 'none', opacity: 1 }, { transform: `translateY(${-dy}em)`, opacity: 0 }], { ...sp, delay: i * 18, fill: "both" }).onfinish = () => o.remove();
        }
      }
      el.appendChild(c);
    }
  }

  const bytes = (b, f = 1) => {
    const u = ['B', 'KB', 'MB', 'GB', 'TB'], p = 10 ** f;
    let v = b, i = 0;
    while (Math.round(v * p) >= 1000 * p && i < u.length - 1) { v /= 1000; i++; }
    return [String(Math.round(v * p) / p), u[i]];
  };

  // Monotone cubic (Fritsch-Carlson), the same curve family the app's charts draw.
  function tangents(xs, ys) {
    const n = xs.length, d = [], m = new Array(n);
    for (let i = 0; i < n - 1; i++) d.push((ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i]));
    m[0] = d[0]; m[n - 1] = d[n - 2];
    for (let i = 1; i < n - 1; i++) m[i] = d[i - 1] * d[i] <= 0 ? 0 : (d[i - 1] + d[i]) / 2;
    for (let i = 0; i < n - 1; i++) {
      if (d[i] === 0) { m[i] = m[i + 1] = 0; continue; }
      const a = m[i] / d[i], b = m[i + 1] / d[i], s = a * a + b * b;
      if (s > 9) { const t = 3 / Math.sqrt(s); m[i] = t * a * d[i]; m[i + 1] = t * b * d[i]; }
    }
    return m;
  }
  const herm = (x0, y0, x1, y1, m0, m1, t) => {
    const h = x1 - x0, t2 = t * t, t3 = t2 * t;
    return (2 * t3 - 3 * t2 + 1) * y0 + (t3 - 2 * t2 + t) * h * m0 + (-2 * t3 + 3 * t2) * y1 + (t3 - t2) * h * m1;
  };
  const f2 = v => v.toFixed(2);
  function pathD(xs, ys, m) {
    let d = `M${f2(xs[0])} ${f2(ys[0])}`;
    for (let i = 0; i < xs.length - 1; i++) {
      const h = (xs[i + 1] - xs[i]) / 3;
      d += `C${f2(xs[i] + h)} ${f2(ys[i] + h * m[i])} ${f2(xs[i + 1] - h)} ${f2(ys[i + 1] - h * m[i + 1])} ${f2(xs[i + 1])} ${f2(ys[i + 1])}`;
    }
    return d;
  }
  const niceStep = v => { if (!(v > 0)) return 1; const b = 10 ** Math.floor(Math.log10(v)); return [1, 2, 2.5, 5, 10].map(k => k * b).find(x => x >= v * .999999) ?? 10 * b; };
  function ceiling(peak, prev, minimum) {
    const t = niceStep(Math.max(minimum, peak * 1.25));
    if (!prev || t >= prev) return t;
    const e = Math.max(prev - (prev - t) * .2, peak);
    return e - t < t * .02 ? t : e;
  }

  // A 60-slot chart that scrolls one slot per second; the newest point rides the dot at the right edge.
  let cid = 0;
  function chart(svg, series, { max = 100, min = 1, dynamic = false } = {}) {
    const w = +svg.getAttribute('width'), h = +svg.getAttribute('height'), n = 60, step = (w - 5) / (n - 1), id = 'k' + cid++;
    svg.innerHTML = `<defs><clipPath id="${id}c"><rect class="cr" x="-1" y="-4" width="${w - 4}" height="${h + 8}"/></clipPath>` +
      series.map((s, i) => s.fill ? `<linearGradient id="${id}g${i}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" style="stop-color:var(${s.color});stop-opacity:var(--fade)"/><stop offset="1" style="stop-color:var(${s.color});stop-opacity:0"/></linearGradient>` : '').join('') +
      `</defs><g clip-path="url(#${id}c)"><g class="mv">` +
      series.map((s, i) => (s.fill ? `<path fill="url(#${id}g${i})"/>` : '') + `<path class="ln" style="stroke:var(${s.color})"/>`).join('') +
      `</g></g><circle class="dot" r="2.5" cx="${w - 5}" style="fill:var(${series[0].color})"/>`;
    const mv = $('.mv', svg), dot = $('.dot', svg), paths = $$('path', svg), cr = $('.cr', svg);
    let M = dynamic ? 0 : max, geo;
    function build() {
      if (dynamic) M = ceiling(Math.max(...series.flatMap(s => s.data)), M, min);
      const xs = series[0].data.map((_, i) => (w - 5) - (n - 1 - i) * step);
      geo = series.map(s => { const ys = s.data.map(v => h - 1.5 - clamp(v / M, 0, 1.04) * (h - 5)); return { xs, ys, m: tangents(xs, ys) }; });
      let k = 0;
      series.forEach((s, i) => {
        const g = geo[i], d = pathD(g.xs, g.ys, g.m);
        if (s.fill) paths[k++].setAttribute('d', `${d}L${f2(g.xs[n])} ${h}L${f2(g.xs[0])} ${h}Z`);
        paths[k++].setAttribute('d', d);
      });
    }
    function at(phase) {
      mv.setAttribute('transform', `translate(${(-phase * step).toFixed(3)} 0)`);
      const g = geo[0];
      dot.setAttribute('cy', f2(herm(g.xs[n - 1], g.ys[n - 1], g.xs[n], g.ys[n], g.m[n - 1], g.m[n], phase)));
    }
    build(); at(0);
    return { build, at, reveal: k => cr.setAttribute('width', (w - 4) * k), series };
  }

  function shape(keys, n, noise, r = rnd) {
    const out = [];
    for (let i = 0; i < n; i++) {
      const x = i / (n - 2);
      let j = 0;
      while (j < keys.length - 2 && keys[j + 1][0] < x) j++;
      const [x0, y0] = keys[j], [x1, y1] = keys[j + 1], t = clamp((x - x0) / (x1 - x0), 0, 1);
      out.push(lerp(y0, y1, t * t * (3 - 2 * t)) + (r() - .5) * noise);
    }
    return out;
  }

  const S = { cpu: 37, cpuBias: 0, gpu: 11, mem: 59.1, down: 550600, up: 66100, bat: 82, burst: 0 };
  const PROCS = {
    xcode: { n: 'Xcode', c: 41.2, m: '1.96 GB', i: 0 },
    safari: { n: 'Safari', c: 12.8, m: '658 MB', i: 1 },
    music: { n: 'Music', c: 4.1, m: '200.3 MB', i: 2 },
    photos: { n: 'Photos', c: 2.6, m: '326.2 MB', i: 3 },
    mail: { n: 'Mail', c: 1.4, m: '177.4 MB', i: 4 },
    ws: { n: 'WindowServer', c: 1.2, m: '312.5 MB', i: -1 },
    spot: { n: 'Spotlight', c: .9, m: '96.4 MB', i: -1 },
  };
  for (const p of Object.values(PROCS)) p.base = p.c;
  let order = ['xcode', 'safari', 'music', 'photos', 'mail'];

  let desk, deskIn, panel, list, charts = {};
  function rowEl(k) {
    const p = PROCS[k];
    if (p.el) return p.el;
    const r = D.createElement('div');
    r.className = 'row'; r.dataset.k = k;
    r.innerHTML = `<span class="ic${p.i < 0 ? ' gen' : ''}"${p.i >= 0 ? ` style="background-position:-20px -${441 + 30 * p.i}px"` : ''}>${p.i < 0 ? '&gt;_' : ''}</span><span class="pn">${p.n}</span><span class="pc"><span class="rn">${p.c.toFixed(1)}</span><span class="u">%</span></span><span class="pm">${p.m}</span>`;
    return p.el = r;
  }
  function placeRows(anim) {
    order.forEach((k, i) => {
      const r = rowEl(k), y = 4 + 30 * i, old = r._y;
      if (!r.parentNode) list.appendChild(r);
      r._y = y; r.style.transform = `translateY(${y}px)`;
      if (anim && old != null && old !== y && on) r.animate([{ transform: `translateY(${old}px)` }, { transform: `translateY(${y}px)` }], spring(.42, .74));
    });
  }
  function removeRow(k) {
    const r = PROCS[k].el;
    order = order.filter(x => x !== k);
    r.classList.remove('hov');
    if (on) {
      r.animate([{ transform: `translateY(${r._y}px)`, opacity: 1 }, { transform: `translate(-14px,${r._y}px)`, opacity: 0 }], { duration: 200, easing: 'cubic-bezier(.4,0,1,1)', fill: 'forwards' }).onfinish = () => { r.remove(); r.getAnimations().forEach(a => a.cancel()); };
      after(110, () => placeRows(true));
    } else { r.remove(); placeRows(false); }
    r._y = null;
  }
  function addRow(k, at = order.length) {
    order.splice(at, 0, k);
    placeRows(true);
    const r = PROCS[k].el, y = r._y;
    if (on) r.animate([{ transform: `translateY(${y + (at === 0 ? -8 : 8)}px)`, opacity: 0 }, { transform: `translateY(${y}px)`, opacity: 1 }], { ...spring(.45, .8), delay: 60, fill: 'backwards' });
  }

  function seedCharts() {
    const cpu = shape([[0, 30], [.06, 36], [.13, 40], [.2, 46], [.27, 47], [.34, 40], [.42, 36], [.5, 28], [.57, 21], [.63, 15], [.69, 22], [.75, 27], [.82, 26], [.88, 31], [.94, 30], [1, 34]], 61, 9);
    cpu[59] = 37; cpu[60] = 38.4;
    const gpu = shape([[0, 10], [.2, 11.6], [.4, 12.2], [.55, 10.6], [.7, 9.6], [.85, 10.2], [1, 11]], 61, .5);
    gpu[59] = 11; gpu[60] = 10.6;
    const down = [], up = [];
    const spikes = { 6: 420e3, 7: 180e3, 17: 640e3, 25: 1050e3, 26: 380e3, 41: 820e3, 42: 260e3, 52: 300e3 };
    for (let i = 0; i < 61; i++) { down.push(spikes[i] ?? (40e3 + rnd() * 70e3)); up.push(40e3 + rnd() * 40e3 + (i % 17 === 3 ? 90e3 : 0)); }
    down[58] = 160e3; down[59] = 550600; down[60] = 210e3; up[59] = 66100; up[60] = 58e3;
    charts.cpu = chart($('#c-cpu'), [{ color: '--cpu', fill: true, data: cpu }], { max: 100 });
    charts.gpu = chart($('#c-gpu'), [{ color: '--gpu', fill: true, data: gpu }], { dynamic: true, min: 10 });
    charts.net = chart($('#c-net'), [{ color: '--down', fill: true, data: down }, { color: '--up', fill: false, data: up }], { dynamic: true, min: 100e3 });
  }

  function sampleCpu() {
    const target = clamp(34 + 6 * Math.sin(vt / 9000) + S.cpuBias + (S.burst ? 42 : 0), 3, 99);
    S.cpu = clamp(lerp(S.cpu, target, .45) + (rnd() - .5) * 5, 2, 99);
    return S.cpu;
  }
  function sampleNet() {
    let d;
    if (S.burst) d = 900e3 + rnd() * 900e3;
    else if (rnd() < .16) d = 280e3 + rnd() * 820e3;
    else d = 35e3 + rnd() * 110e3;
    const u = rnd() < .1 ? 140e3 + rnd() * 120e3 : 30e3 + rnd() * 60e3;
    return [d, u];
  }

  function stepCharts() {
    const c = charts.cpu.series[0].data; c.shift(); c.push(sampleCpu());
    const g = charts.gpu.series[0].data; g.shift(); S.gpu = clamp(lerp(S.gpu, 11 + S.cpuBias * .15 + (S.burst ? 20 : 0), .4) + (rnd() - .5) * 2.2, 2, 99); g.push(S.gpu);
    const [d, u] = sampleNet(), nd = charts.net.series[0].data, nu = charts.net.series[1].data;
    nd.shift(); nd.push(d); nu.shift(); nu.push(u);
    for (const k in charts) charts[k].build();
    S.down = nd[59]; S.up = nu[59];
    const [dv, du] = bytes(S.down), [uv, uu] = bytes(S.up);
    roll($('#v-down'), dv, .25); $('#v-downu').textContent = du + '/s';
    roll($('#v-up'), uv, .25); $('#v-upu').textContent = uu + '/s';
  }

  function startLive() {
    let tStep = vt;
    frames.add(t => { const ph = clamp((t - tStep) / 1000, 0, 1); for (const k in charts) charts[k].at(ph); });
    every(1000, () => { stepCharts(); tStep = vt; }, 1000);
    every(2000, () => {
      const v = Math.round(charts.cpu.series[0].data[59]), u = Math.round(v * .62);
      roll($('#v-cpu'), String(v)); roll($('#v-user'), String(u)); roll($('#v-sys'), String(v - u));
    }, 1150);
    every(2000, () => roll($('#v-gpu'), String(Math.round(charts.gpu.series[0].data[59]))), 1300);
    every(4000, () => {
      S.mem = clamp(S.mem + (rnd() - .5) * 1.4 + (S.burst ? .9 : 0), 55, 72);
      roll($('#v-mem'), String(Math.round(S.mem)), .6);
      roll($('#v-memu'), (24 * S.mem / 100).toFixed(2), .6);
      $('#b-mem').style.setProperty('--p', S.mem + '%');
    }, 1450);
    every(40000, () => { if (S.bat < 100) { S.bat++; roll($('#v-bat'), String(S.bat), .6); $('#b-bat').style.setProperty('--p', S.bat + '%'); } }, 20000);
    every(2000, () => {
      for (const k of order) {
        const p = PROCS[k];
        if (p.lock) continue;
        p.c = Math.max(.1, p.base * (1 + (rnd() - .5) * .16) + (k === 'xcode' && S.burst ? 30 : 0));
        roll($('.pc .rn', rowEl(k)), p.c.toFixed(1), .5);
      }
    }, 1600);
  }

  function layout() {
    const vw = R.host.clientWidth, vh = R.host.clientHeight, phone = vw < 640;
    const stack = phone || vw / clamp(Math.min(1.3, vh / 693), .55, 1.3) < (api.sideMin || 554);
    const extra = stack ? (api.below || 0) : 0, need = 29 + 642 + 22 + extra;
    const z = phone ? 1 : clamp(Math.min(1.3, vh / need), .55, 1.3);
    const W = vw / z, H = Math.max(vh / z, need);
    Object.assign(deskIn.style, { width: W + 'px', height: H + 'px', transform: `scale(${z})` });
    desk.style.height = H * z + 'px';
    const mbi = $('.mbi'), mx = mbi.offsetLeft + mbi.offsetWidth / 2;
    const x = phone ? (W - 356) / 2 : clamp(mx - 178, 14, W - 356 - 14);
    panel.style.left = x + 'px';
    Object.assign(api, { z, W, H, phone, stack, px: x });
    api.onLayout && api.onLayout();
    cursor.place(cur.x, cur.y);
  }

  function enter() {
    panel.style.transformOrigin = '50% 0';
    panel.animate([{ opacity: 0, transform: 'translateY(-5px) scale(.985)' }, { opacity: 1, transform: 'none' }], spring(.36, .9));
    $$('[data-in]', panel).forEach((el, i) => el.animate([{ opacity: 0, transform: 'translateY(8px)' }, { opacity: 1, transform: 'none' }], { ...spring(.5, .8), delay: 70 + i * 30, fill: 'backwards' }));
    for (const k in charts) { charts[k].reveal(0); after(220, () => tween(450, e => charts[k].reveal(e), t => 1 - Math.pow(1 - t, 3))); }
  }

  // Cursor in panel coordinates.
  const cur = { x: 300, y: 560 };
  let curEl;
  const cursor = {
    show() { curEl.classList.add('on'); },
    hide() { curEl.classList.remove('on'); },
    place(x, y) { cur.x = x; cur.y = y; curEl.style.transform = `translate(${x - 2 + panel.offsetLeft}px,${y - 2 + panel.offsetTop}px)`; },
    move(x, y, ms = 600) { const x0 = cur.x, y0 = cur.y; return tween(ms, e => cursor.place(lerp(x0, x, e), lerp(y0, y, e))); },
    async click() { curEl.classList.add('dn'); await sleep(120); curEl.classList.remove('dn'); },
  };
  function rel(el) {
    const a = el.getBoundingClientRect(), p = panel.getBoundingClientRect(), z = api.z;
    return { x: (a.left - p.left) / z, y: (a.top - p.top) / z, w: a.width / z, h: a.height / z };
  }
  const toPanel = (cx, cy) => { const p = panel.getBoundingClientRect(); return { x: (cx - p.left) / api.z, y: (cy - p.top) / api.z }; };

  function setMode(m) {
    const seg = $('#seg'), th = $('#thumb');
    $$('[data-m]', seg).forEach(s => s.classList.toggle('on', s.dataset.m === m));
    const s = $(`[data-m="${m}"]`, seg), x = s.offsetLeft, w = s.offsetWidth;
    th.style.transform = `translateX(${x}px)`;
    $('.m', th).style.transform = `scaleX(${w - 10})`;
    $('.r', th).style.transform = `translateX(${w - 6}px)`;
    api.mode = m;
  }

  function init() {
    desk = $('.desk'); deskIn = $('.desk-in'); panel = $('#panel'); list = $('#list');
    curEl = D.createElement('div'); curEl.className = 'cur';
    curEl.innerHTML = '<svg width="18" height="26" viewBox="0 0 18 26" aria-hidden="true"><path d="M2 1.6v19.6l4.7-4.5 3.1 7.1 3.3-1.4-3.1-7h6.5z" fill="#000" stroke="#fff" stroke-width="1.3" stroke-linejoin="round"/></svg>';
    deskIn.appendChild(curEl);
    cursor.place(cur.x, cur.y);
    placeRows(false);
    seedCharts();
    setMode('custom');
    layout();
    new ResizeObserver(() => layout()).observe(R.host);
    if (OVERLAY) { const o = D.createElement('div'); o.className = 'ov'; panel.appendChild(o); }
    api.onReady && api.onReady();
    if (STILL) { api.onStill && api.onStill(); return; }
    startLive();
    const io = new IntersectionObserver(es => run(es[0].isIntersecting && !D.hidden), { threshold: .2 });
    io.observe(desk);
    D.addEventListener('visibilitychange', () => run(!D.hidden && desk.getBoundingClientRect().bottom > 0 && desk.getBoundingClientRect().top < innerHeight));
  }

  const api = { init, after, every, sleep, tween, roll, spring, bytes, S, PROCS, rowEl, removeRow, addRow, placeRows, cursor, rel, toPanel, setMode, frames, clamp, lerp, rnd, STILL, RM, OVERLAY, $, $$, get order() { return order; }, set order(v) { order = v; }, get on() { return on; }, get vt() { return vt; } };
  return api;
})();

}
{
const E = engine(mount('live'));
// A build kicks in every 14 s: CPU, GPU, Xcode and the network jump, then settle.
E.onStart = () => {
  E.every(14000, () => { E.S.burst = 1; E.after(4200, () => { E.S.burst = 0; }); }, 6000);
};
E.init();
}
{
const E = engine(mount('fan'));
(() => {
  const { $, $$, sleep, after, tween, cursor, rel, clamp, lerp } = E;
  // FanCurve.swift: user points plus the locked end (an 80 °C CPU average, full speed), monotone cubic, flat below the
  // first point, on the 30-90 °C average scale. EDITED is a hottest-core Custom curve moved through averageScale.
  const LOCK = [80, 1], TOP = 90, MIN_RPM = 1350, MAX_RPM = 5777;
  const EDITED = [[49, .32], [61, .53], [67, .59]], STANDARD = [[50, 0]];
  const PRESETS = { silent: [[50, 0], [60, .12], [68, .25], [74, .4]], quiet: [[48, 0], [58, .15], [66, .32], [73, .5]], steady: [[45, 0], [55, .25], [63, .5], [70, .75]] };
  function speedAt(pts, c) {
    const p = [...pts, LOCK];
    if (c <= p[0][0]) return p[0][1];
    if (c >= LOCK[0]) return 1;
    const s = [];
    for (let i = 0; i < p.length - 1; i++) s.push((p[i + 1][1] - p[i][1]) / (p[i + 1][0] - p[i][0]));
    const m = [s[0]];
    for (let i = 1; i < s.length; i++) m.push(s[i - 1] * s[i] <= 0 ? 0 : (s[i - 1] + s[i]) / 2);
    m.push(s[s.length - 1]);
    s.forEach((d, k) => {
      if (d === 0) { m[k] = 0; m[k + 1] = 0; return; }
      const a = m[k] / d, b = m[k + 1] / d, l = a * a + b * b;
      if (l > 9) { const t = 3 / Math.sqrt(l); m[k] = t * a * d; m[k + 1] = t * b * d; }
    });
    const u = p.findIndex(q => q[0] >= c), k = u - 1, lo = p[k], hi = p[u], w = hi[0] - lo[0], t = (c - lo[0]) / w, t2 = t * t, t3 = t2 * t;
    const v = (2 * t3 - 3 * t2 + 1) * lo[1] + (t3 - 2 * t2 + t) * w * m[k] + (-2 * t3 + 3 * t2) * hi[1] + (t3 - t2) * w * m[u];
    return clamp(v, lo[1], hi[1]);
  }
  console.assert(speedAt(EDITED, 80) === 1 && speedAt(EDITED, 90) === 1 && speedAt(EDITED, 40) === .32, "curve must be flat below the first point and full from 80 °C");
  // FanHold.next: PI loop on 1 s ticks, nothing changes inside target ± 2 °C.
  class Hold {
    constructor(target, speed) { this.target = target; this.speed = clamp(speed, 0, 1); this.integral = this.speed; }
    next(c) {
      const e = c - this.target;
      if (Math.abs(e) <= 2) return this.speed;
      const learned = this.integral + .002 * e, raw = .05 * e + learned;
      if ((raw < 1 || e < 0) && (raw > 0 || e > 0)) this.integral = clamp(learned, 0, 1);
      const want = clamp(.05 * e + this.integral, 0, 1);
      this.speed += clamp(want - this.speed, -.03, .03);
      return this.speed;
    }
  }
  // CPUHeat.swift steps on the average scale.
  const step = c => c < 46 ? 0 : c < 57 ? 1 : c < 68 ? 2 : c < 76 ? 3 : 4;
  const heatVar = c => ['--t-cool', '--t-warm', '--t-hot', '--t-very-hot', '--t-near-the-limit'][step(c)];
  const heatWord = c => ['normal', 'warm', 'hot', 'very hot', 'near the limit'][step(c)];
  const panelHeat = c => ['normal', 'warm', 'hot', 'very-hot', 'near-the-limit'][step(c)];
  const rpmText = s => Math.round(MIN_RPM + s * (MAX_RPM - MIN_RPM)).toLocaleString('en-US');
  const springF = (t, resp = .55, damp = .78) => {
    if (t <= 0) return 0;
    const w = 2 * Math.PI / resp, a = damp * w, wd = w * Math.sqrt(1 - damp * damp);
    return 1 - Math.exp(-a * t) * (Math.cos(wd * t) + a / wd * Math.sin(wd * t));
  };

  const fp = $('#fp'), fg = $('#fg'), fch = $('#fch'), svg = $('#cv'), chip = $('#chip'), panel = $('#panel');
  const fanG = $('.g[data-g=fan]', panel);
  const N = (TOP - 30) * 2 + 1, cAt = i => 30 + i / 2;
  const samples = pts => Array.from({ length: N }, (_, i) => speedAt(pts, cAt(i)));
  let custom = EDITED, pick = 'custom', temp = 64, holdT = 62, hold = null, sim = false, manual = false;
  let disp = samples(EDITED), from = null, to = null, m0 = 0, shown = speedAt(EDITED, 64), angle = 0, token = 0, idle = null;
  let CW = 540, CH = 240;
  const PT = 22, PB = 22;
  const X = c => CW * (c - 30) / (TOP - 30), Y = s => PT + (CH - PT - PB) * (1 - s);
  const curvePts = () => PRESETS[pick] || custom;
  const dispAt = c => { const f = clamp((c - 30) * 2, 0, N - 1), i = Math.min(N - 2, Math.floor(f)); return lerp(disp[i], disp[i + 1], f - i); };
  const NS = 'http://www.w3.org/2000/svg';
  let knobs = [];

  function buildGrid() {
    let h = '';
    for (const s of [0, .5, 1]) h += `<path class="gl" d="M0 ${Y(s)}H${CW}"/><text class="glab" x="12" y="${Y(s) - 4.5}">${s * 100}%</text>`;
    for (let c = 40; c <= LOCK[0]; c += 10) h += `<text class="glab" x="${X(c)}" y="${CH - PB + 15.5}" text-anchor="middle">${c === LOCK[0] ? c + ' °C' : c}</text>`;
    $('#grid').innerHTML = h;
    $('#hg').setAttribute('x2', CW);
    Object.entries({ x: 0, y: PT - 4, width: CW, height: CH - PT - PB + 4 }).forEach(([k, v]) => $('#hmr').setAttribute(k, v));
    $('#lkd').setAttribute('transform', `translate(${X(LOCK[0])} ${Y(1)})`);
    Object.entries({ x: X(LOCK[0]) - 16, y: PT - 7 }).forEach(([k, v]) => $('#lkt').setAttribute(k, v));
    Object.entries({ x1: X(LOCK[0]), y1: Y(1), x2: CW, y2: Y(1) }).forEach(([k, v]) => $('#hflat').setAttribute(k, v));
  }
  function setKnobs(pts) {
    knobs.forEach(k => { if (E.on) k.el.animate([{ opacity: 1 }, { opacity: 0 }], { duration: 220, fill: 'forwards' }).onfinish = () => k.el.remove(); else k.el.remove(); });
    knobs = pts.map(([c]) => {
      const el = document.createElementNS(NS, 'circle');
      el.setAttribute('r', 4.75); el.setAttribute('class', 'kn'); el.style.stroke = `var(${heatVar(c)})`;
      $('#kns').appendChild(el);
      if (E.on) el.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 260, delay: 120, fill: 'backwards' });
      return { c, el };
    });
  }
  function drawHold() {
    const x0 = X(holdT - 2), x1 = X(holdT + 2);
    Object.entries({ x: x0, y: PT, width: x1 - x0, height: CH - PT - PB }).forEach(([k, v]) => $('#hb').setAttribute(k, v));
    Object.entries({ x1: X(holdT), y1: Y(0), x2: X(holdT), y2: Y(1) }).forEach(([k, v]) => $('#hl').setAttribute(k, v));
    Object.entries({ x: x0 - 8, y: PT + 14 }).forEach(([k, v]) => $('#ht').setAttribute(k, v));
    $('#ht').textContent = `Hold ${holdT} °C`;
    $('#pkh').textContent = `Hold ${holdT} °C`;
    $('#hht').textContent = holdT; $('#hv2').textContent = holdT;
    drawMini($('.pk[data-p=hold] svg'), null);
  }
  function drawMini(el, pts) {
    const w = el.clientWidth || 80, h = 30, x = c => 2 + (w - 4) * (c - 30) / (TOP - 30), y = s => 2 + 26 * (1 - s);
    if (!pts) {
      el.innerHTML = `<rect x="${x(holdT - 2)}" y="2" width="${x(holdT + 2) - x(holdT - 2)}" height="26" fill="currentColor" fill-opacity=".12"/><path d="M${x(holdT)} 28V2" stroke="currentColor" stroke-width="1.5" stroke-dasharray="3 2"/>`;
      return;
    }
    let d = '';
    for (let c = 30; c <= TOP; c += 1) d += (c === 30 ? 'M' : 'L') + x(c).toFixed(1) + ' ' + y(speedAt(pts, c)).toFixed(1);
    el.innerHTML = `<path d="${d}L${x(TOP)} 28L${x(30)} 28Z" fill="currentColor" fill-opacity=".12"/><path d="${d}" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>`;
  }
  function drawMinis() { for (const p in PRESETS) drawMini($(`.pk[data-p=${p}] svg`), PRESETS[p]); drawMini($('.pk[data-p=custom] svg'), custom); drawHold(); }

  const targetSpeed = () => E.mode === 'auto' ? 0 : E.mode === 'max' ? 1 : hold ? hold.speed : speedAt(curvePts(), temp);
  function render() {
    let d = '';
    for (let i = 0; i < N; i++) d += (i ? 'L' : 'M') + X(cAt(i)).toFixed(1) + ' ' + Y(clamp(disp[i], -.03, 1.03)).toFixed(1);
    $('#cl').setAttribute('d', d);
    $('#ca').setAttribute('d', d + `L${CW} ${Y(0)}L0 ${Y(0)}Z`);
    knobs.forEach(k => { k.el.setAttribute('cx', X(k.c)); k.el.setAttribute('cy', Y(clamp(dispAt(k.c), 0, 1))); });
    const x = X(clamp(temp, 30, TOP)), hv = `var(${heatVar(temp)})`;
    const nd = $('#nd');
    nd.setAttribute('cx', x); nd.setAttribute('cy', Y(clamp(dispAt(temp), 0, 1))); nd.style.fill = hv;
    nd.style.filter = `drop-shadow(0 0 4px color-mix(in srgb, ${hv} 50%, transparent))`;
    Object.entries({ x1: x, y1: Y(0), x2: x, y2: PT + 52 }).forEach(([k, v]) => $('#nl').setAttribute(k, v));
    $('#nl').style.stroke = hv;
    const n2 = $('#nd2'); n2.setAttribute('cx', x); n2.setAttribute('cy', Y(0)); n2.style.fill = hv;
    const t = Math.round(temp), r = rpmText(shown);
    chip.textContent = `CPU avg ${t} °C · ${r} RPM`;
    if (hold) {
      const away = temp >= holdT;
      chip.style.transform = `translate(${x + (away ? 6 : -6)}px,${12 + PT + 52}px) translate(${away ? 0 : -100}%,-50%)`;
    } else chip.style.transform = `translate(${x}px,${12 + Y(clamp(dispAt(temp), 0, 1)) - 22}px) translate(-50%,-50%)`;
    $('#now').textContent = `CPU avg ${t} °C · ${heatWord(t)} · ${r} RPM`;
  }
  let lastPanel = '';
  function paintPanel() {
    const r = rpmText(shown);
    if (r !== lastPanel) { E.roll($('#v-rpm'), r, .5); lastPanel = r; }
    $('#therm').style.setProperty('--heat', `var(--t-${panelHeat(temp)})`);
    E.S.cpuBias = (temp - 44) * 1.3;
  }
  function snap() { if (from) { disp = to; from = null; } shown = targetSpeed(); render(); paintPanel(); }

  function choose(p) {
    $$('.pk').forEach(k => k.classList.toggle('on', k.dataset.p === p));
    const wasHold = !!hold;
    if (p === 'hold') {
      temp = holdT; hold = new Hold(holdT, speedAt(curvePts(), holdT));
      $('#L-curve').style.opacity = 0; $('#L-now').style.opacity = 0; $('#L-hold').style.opacity = 1;
      $('#hc').classList.add('off'); $('#hh').classList.remove('off');
    } else {
      hold = null; pick = p;
      $('#L-curve').style.opacity = 1; $('#L-now').style.opacity = 1; $('#L-hold').style.opacity = 0;
      $('#hc').classList.remove('off'); $('#hh').classList.add('off');
      const pts = curvePts();
      from = wasHold ? null : disp.slice(); to = samples(pts); m0 = E.vt;
      if (wasHold) disp = to;
      setKnobs(pts);
    }
    $('#rst').disabled = !(pick === 'custom' && !hold && custom !== STANDARD);
    coolLabel();
    if (!E.on) snap();
  }
  // FanControlView.isCustom: the Cool segment reads "Custom" only while the owner's own curve is the pick.
  function coolLabel() {
    $('[data-m=custom]').textContent = pick === 'custom' && !hold ? 'Custom' : 'Cool';
    if (E.mode) E.setMode(E.mode);
  }
  coolLabel();
  function mode(m) {
    E.setMode(m);
    fg.classList.toggle('dim', m !== 'custom');
    $('#fmo').textContent = m === 'auto' ? 'Auto follows macOS' : 'Max runs fans at their hardware maximum';
    if (!E.on) snap();
  }

  E.below = 450;
  E.sideMin = 14 + 568 + 20 + 356 + 14;
  E.onLayout = () => {
    const sm = E.stack;
    fp.classList.toggle('sm', sm);
    if (sm) { fp.style.left = E.px + 'px'; fp.style.top = (29 + 642 + 16) + 'px'; }
    else {
      let px = E.px;
      if (px < 14 + 568 + 20) { px = Math.min(E.W - 356 - 14, 14 + 568 + 20); panel.style.left = px + 'px'; E.px = px; }
      fp.style.left = (px - 20 - 568) + 'px'; fp.style.top = (29 + 70) + 'px';
    }
    CW = fch.clientWidth; CH = sm ? 200 : 240;
    svg.setAttribute('width', CW); svg.setAttribute('height', CH);
    buildGrid(); drawMinis(); render();
  };

  async function click(el) {
    const r = rel(el);
    await cursor.move(r.x + r.w / 2, r.y + r.h * .55, 700);
    await sleep(160); await cursor.click();
  }
  async function loop(t) {
    const alive = () => t === token;
    manual = false;
    if (E.mode !== 'custom') mode('custom');
    if (custom !== EDITED) { custom = EDITED; drawMinis(); }
    if (hold || pick !== 'custom') choose('custom');
    else { from = disp.slice(); to = samples(EDITED); m0 = E.vt; setKnobs(EDITED); }
    const p0 = rel($('.pk[data-p=steady]'));
    cursor.place(p0.x + 30, p0.y + 90); cursor.show();
    while (alive()) {
      await sleep(700); if (!alive()) return;
      const t0 = temp;
      await tween(3200, e => alive() && (temp = lerp(t0, 64, e)));
      if (!alive()) return;
      for (const p of ['silent', 'steady']) {
        await click($(`.pk[data-p=${p}]`)); if (!alive()) return;
        choose(p);
        await sleep(2200); if (!alive()) return;
      }
      await click($('.pk[data-p=hold]')); if (!alive()) return;
      choose('hold'); sim = true;
      await sleep(10000); sim = false; if (!alive()) return;
      await click($('.pk[data-p=custom]')); if (!alive()) return;
      choose('custom');
      await sleep(1200); if (!alive()) return;
      const t1 = temp;
      await tween(3600, e => alive() && (temp = lerp(t1, 50, e)));
      if (!alive()) return;
      await sleep(600);
    }
  }
  function takeOver() {
    token++; sim = false; manual = true; cursor.hide();
    if (idle) idle.t = Infinity;
    idle = after(8000, () => loop(++token));
  }

  let dragging = false;
  const tempFrom = e => { const b = svg.getBoundingClientRect(); return clamp(30 + (TOP - 30) * (e.clientX - b.left) / b.width, 30, TOP); };
  fch.addEventListener('pointerdown', e => { takeOver(); dragging = true; fch.setPointerCapture(e.pointerId); temp = tempFrom(e); if (!E.on) snap(); });
  fch.addEventListener('pointermove', e => { if (!dragging) return; temp = tempFrom(e); if (!E.on) snap(); });
  fch.addEventListener('pointerup', () => { dragging = false; });
  $$('.pk').forEach(k => k.addEventListener('click', () => { takeOver(); if (E.mode !== 'custom') mode('custom'); choose(k.dataset.p); }));
  $$('.stp button').forEach(b => b.addEventListener('click', () => { takeOver(); holdT = clamp(holdT + +b.dataset.d, 56, 70); if (hold) hold.target = holdT; drawHold(); if (!E.on) snap(); }));
  $('#rst').addEventListener('click', () => { takeOver(); custom = STANDARD; drawMini($('.pk[data-p=custom] svg'), custom); choose('custom'); });
  $$('[data-m]', panel).forEach(s => s.addEventListener('click', () => { takeOver(); mode(s.dataset.m); }));

  E.onReady = () => { setKnobs(EDITED); drawMinis(); snap(); };
  E.onStart = () => {
    temp = 50;
    E.frames.add((t, dt) => {
      if (from) { const k = (t - m0) / 1000; const e = springF(k); disp = from.map((v, i) => v + (to[i] - v) * e); if (k > 1.3) { disp = to; from = null; } }
      if (sim) temp += (72 - 18 * shown + .6 * Math.sin(t / 1500) - temp) * Math.min(1, dt / 3000);
      shown += (targetSpeed() - shown) * Math.min(1, dt / 1000 * 2.5);
      angle = (angle + dt / 1000 * (0.4 + shown * 3) * 360) % 360;
      fanG.style.transform = `rotate(${angle.toFixed(1)}deg)`;
      render();
    });
    E.every(1000, () => { if (hold && E.mode === 'custom') hold.next(temp); });
    E.every(400, paintPanel);
    loop(token);
  };
})();
E.init();
E.init();
}
})();
