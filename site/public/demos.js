// The live menu panel demo in the hero. It renders in its own shadow root on the .demo host.
(async () => {
const [css, html] = await Promise.all(['demo.css', 'panel.html'].map(f => fetch(f).then(r => r.text())));
const sheet = new CSSStyleSheet();
sheet.replaceSync(css);
function mount(name) {
  const host = document.querySelector('[data-demo=' + name + ']'), R = host.attachShadow({ mode: 'open' });
  R.adoptedStyleSheets = [sheet];
  R.innerHTML = html;
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
      if (!started) { started = true; api.onStart && api.onStart(); }
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

  // Numbers change in place; nothing slides.
  function roll(el, text) {
    if (!el || (el.dataset.v ?? el.textContent) === text) return;
    el.dataset.v = text; el.textContent = text;
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
    });
  }
  function removeRow(k) {
    const r = PROCS[k].el;
    order = order.filter(x => x !== k);
    r.classList.remove('hov');
    r.remove(); placeRows(false);
    r._y = null;
  }
  function addRow(k, at = order.length) {
    order.splice(at, 0, k);
    placeRows(true);
    const r = PROCS[k].el, y = r._y;
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
    // On a phone a demo may crop off the panel above its own part (cropTop), so that part reads at full size.
    const top = phone && api.cropTop || 0, cut = top ? api.cropBottom || 0 : 0;
    const extra = stack ? (api.below || 0) : 0, need = 29 + 642 + 22 + extra - top - cut;
    const z = phone ? Math.min(1, vh / need) : clamp(Math.min(1.3, vh / need), .55, 1.3);
    const W = vw / z, H = Math.max(vh / z, need) + top;
    Object.assign(deskIn.style, { width: W + 'px', height: H + 'px', transform: `scale(${z}) translateY(${-top}px)` });
    desk.style.height = (H - top) * z + 'px';
    deskIn.classList.toggle("crop", !!top);
    const mbi = $('.mbi'), mx = mbi.offsetLeft + mbi.offsetWidth / 2;
    const x = phone ? (W - 356) / 2 : clamp(mx - 178, 14, W - 356 - 14);
    panel.style.left = x + 'px';
    Object.assign(api, { z, W, H, phone, stack, px: x });
    api.onLayout && api.onLayout();
    cursor.place(cur.x, cur.y);
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
})();
