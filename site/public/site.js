(function () {
  function flash(el) {
    el.classList.add('done');
    setTimeout(function () { el.classList.remove('done'); }, 1400);
  }
  function copy(text) {
    if (navigator.clipboard) navigator.clipboard.writeText(text).catch(function () {});
  }

  document.addEventListener('click', function (e) {
    var b = e.target.closest('[data-copy]');
    if (b) { copy(b.getAttribute('data-copy')); flash(b.closest('.cmd')); return; }
    var a = e.target.closest('.anchor');
    if (a) {
      e.preventDefault();
      var hash = a.getAttribute('href');
      history.replaceState(null, '', hash);
      copy(location.origin + location.pathname + hash);
      flash(a);
    }
  });

  // Fan: the Fan page picks with the app's own math (FanCurve.swift): a monotone cubic through the points and
  // the locked end, full speed from 90 °C. Hold is FanHold's PI loop, one step a second (FanDriver.swift).
  var PICKS = { silent: [[75, 0], [85, 0.3]], quiet: [[68, 0], [78, 0.2], [85, 0.45]],
    steady: [[60, 0], [70, 0.2], [80, 0.45], [86, 0.7]], custom: [[65, 0]] };
  var MIN_RPM = 1350, MAX_RPM = 5777, HOLD = 75, BAND = 2;
  function clamp(v, lo, hi) { return Math.min(Math.max(v, lo), hi); }
  function tangents(p) {
    var s = p.slice(1).map(function (q, i) { return (q[1] - p[i][1]) / (q[0] - p[i][0]); });
    var m = [s[0]].concat(s.slice(1).map(function (v, i) { return s[i] * v <= 0 ? 0 : (s[i] + v) / 2; }), [s[s.length - 1]]);
    s.forEach(function (v, k) {
      if (!v) { m[k] = m[k + 1] = 0; return; }
      var a = m[k] / v, b = m[k + 1] / v, l = a * a + b * b;
      if (l > 9) { var q = 3 / Math.sqrt(l); m[k] = q * a * v; m[k + 1] = q * b * v; }
    });
    return m;
  }
  function curveSpeed(points, c) {
    var p = points.concat([[90, 1]]), m = tangents(p);
    if (c <= p[0][0]) return p[0][1];
    if (c >= 90) return 1;
    var u = p.findIndex(function (q) { return q[0] >= c; }), k = u - 1;
    var lo = p[k], hi = p[u], w = hi[0] - lo[0], t = (c - lo[0]) / w, t2 = t * t, t3 = t2 * t;
    var v = (2 * t3 - 3 * t2 + 1) * lo[1] + (t3 - 2 * t2 + t) * w * m[k]
      + (-2 * t3 + 3 * t2) * hi[1] + (t3 - t2) * w * m[u];
    return clamp(v, lo[1], hi[1]);
  }
  // One FanHold.next tick: nothing changes inside the ±2 °C band, else a PI step of at most 3% a second.
  function holdStep(h, c) {
    var e = c - HOLD;
    if (Math.abs(e) <= BAND) return;
    var learned = h.integral + 0.002 * e, raw = 0.05 * e + learned;
    if ((raw < 1 || e < 0) && (raw > 0 || e > 0)) h.integral = clamp(learned, 0, 1);
    h.speed += clamp(clamp(0.05 * e + h.integral, 0, 1) - h.speed, -0.03, 0.03);
  }
  // CPUHeat.swift: the word and color step for each temperature.
  function heat(c) { return c < 56 ? 'normal' : c < 70 ? 'warm' : c < 85 ? 'hot' : c < 95 ? 'very hot' : 'near the limit'; }

  function fan() {
    var root = document.querySelector('[data-fan]');
    if (!root) return;
    var $ = function (id) { return document.getElementById(id); };
    var input = $('heat'), rpmOut = $('fan-rpm'), tempOut = $('fan-temp'), wordOut = $('fan-word');
    var dot = $('fan-dot'), guide = $('fan-guide'), blades = root.querySelector('.blades');
    var X = function (c) { return (c - 30) / 70 * 320; }, Y = function (s) { return 120 - s * 112; };
    var buttons = root.querySelectorAll('[data-pick]');
    // The curve as 141 speeds, one every 0.5 °C from 30 to 100; a pick morphs from the old list to the new one.
    function samples(points) { var a = []; for (var i = 0; i <= 140; i++) a.push(curveSpeed(points, 30 + i / 2)); return a; }
    function at(list, c) { var i = clamp((c - 30) * 2, 0, 140), k = Math.floor(i), f = i - k; return k >= 140 ? list[140] : list[k] + (list[k + 1] - list[k]) * f; }
    var pick = 'custom', cur = samples(PICKS.custom), from = cur, to = cur, morph = 1, hold = null, tick = 0;
    function drawCurve() {
      var d = cur.map(function (s, i) { return (i ? 'L' : 'M') + X(30 + i / 2).toFixed(1) + ' ' + Y(s).toFixed(1); }).join('');
      $('fan-line').setAttribute('d', d);
      $('fan-area').setAttribute('d', d + 'L320 120L0 120Z');
    }
    function choose(name) {
      if (name === pick) return;
      buttons.forEach(function (b) { b.setAttribute('aria-checked', b.dataset.pick === name ? 'true' : 'false'); });
      root.dataset.pick = name;
      clearInterval(tick); hold = null;
      if (name === 'hold') {
        // The try-it CPU moves to the target, and the loop starts bumpless from the curve's speed there, like
        // FanDriver; starting from a drag to 95 °C would show full speed at 75 °C while the loop ramps down.
        var now = at(cur, HOLD);
        hold = { speed: now, integral: now };
        target = HOLD; input.value = HOLD;
        if (calm.matches) shown = HOLD;
        tick = setInterval(function () { if (visible) { holdStep(hold, shown); if (!raf) paint(); } }, 1000);
      } else {
        from = cur; to = samples(PICKS[name]); morph = calm.matches ? 1 : 0;
        if (morph) { cur = to; drawCurve(); }
      }
      pick = name;
      if (calm.matches) paint(); else wake();
    }
    function speedNow() { return hold ? (shown >= 90 ? 1 : hold.speed) : at(cur, shown); }
    drawCurve();
    // Each pick card shows its curve on the same 30-100 °C scale as the Fan page cards; Hold shows its target.
    buttons.forEach(function (b) {
      var svg = b.querySelector('.mini'), x = function (c) { return 4 + (c - 30) / 70 * 92; };
      if (b.dataset.pick === 'hold') {
        svg.innerHTML = '<path class="target" d="M' + x(HOLD) + ' 4V40"/>';
        return;
      }
      var s = samples(PICKS[b.dataset.pick]);
      var d = s.map(function (v, i) { return (i ? 'L' : 'M') + x(30 + i / 2).toFixed(1) + ' ' + (40 - v * 36).toFixed(1); }).join('');
      svg.innerHTML = '<path class="fill" d="' + d + 'L96 40L4 40Z"/><path class="stroke" d="' + d + '"/>';
    });

    var calm = matchMedia('(prefers-reduced-motion: reduce)');
    var target = +input.value, shown = target, angle = 0, last = 0, raf = 0, visible = false, demo = [], auto = false;
    function paint() {
      var c = shown, s = speedNow(), rounded = Math.round(c), word = heat(rounded);
      var rpm = Math.round(MIN_RPM + s * (MAX_RPM - MIN_RPM));
      dot.setAttribute('cx', X(c)); dot.setAttribute('cy', Y(s));
      guide.setAttribute('x1', X(c)); guide.setAttribute('x2', X(c)); guide.setAttribute('y1', Y(s));
      root.style.setProperty('--f', ((c - 30) / 70).toFixed(4));
      rpmOut.textContent = rpm.toLocaleString('en-US');
      tempOut.textContent = rounded;
      wordOut.textContent = word;
      root.dataset.heat = word.replace(/ /g, '-');
      input.setAttribute('aria-valuetext', rounded + ' °C, ' + word + ', ' + rpm.toLocaleString('en-US') + ' RPM');
      return s;
    }
    function frame(now) {
      var dt = last ? Math.min((now - last) / 1000, 0.1) : 0;
      last = now;
      shown += (target - shown) * Math.min(1, dt * 7);
      if (Math.abs(target - shown) < 0.02) shown = target;
      if (auto) input.value = Math.round(shown);
      if (morph < 1) {
        morph = Math.min(1, morph + dt / 0.55);
        var e = 1 - Math.pow(1 - morph, 3);
        cur = from.map(function (v, i) { return v + (to[i] - v) * e; });
        drawCurve();
      }
      var s = paint();
      // About 0.4 turns a second at the slowest and 3.4 at full speed.
      angle = (angle + dt * (0.4 + s * 3) * 360) % 360;
      blades.style.transform = 'rotate(' + angle + 'deg)';
      raf = visible && !calm.matches ? requestAnimationFrame(frame) : 0;
    }
    function wake() { if (!raf && visible && !calm.matches) { last = 0; raf = requestAnimationFrame(frame); } }
    function stopDemo() { demo.forEach(clearTimeout); demo = []; auto = false; }
    buttons.forEach(function (b) { b.addEventListener('click', function () { stopDemo(); choose(b.dataset.pick); }); });
    input.addEventListener('input', function () {
      stopDemo();
      target = +input.value;
      if (calm.matches) { shown = target; paint(); } else wake();
    });
    new IntersectionObserver(function (es) {
      visible = es[0].isIntersecting;
      if (!visible) return;
      wake();
      // The first time it shows, step through the picks once, unless someone already touched it:
      // the curve morphs, then Hold keeps the speed steady while the CPU sits inside its band.
      if (!calm.matches && !root.dataset.played) {
        root.dataset.played = "1"; auto = true;
        demo = [[700, 'silent'], [2100, 'steady'], [3500, 'hold', 76], [7500, 'custom', 79]].map(function (step) {
          return setTimeout(function () { choose(step[1]); if (step[2]) target = step[2]; }, step[0]);
        });
      }
    }, { threshold: 0.4 }).observe(root);
    paint();
  }

  // Portman: four step buttons switch what the screen shows.
  function walk() {
    var root = document.querySelector('[data-walk]');
    if (!root) return;
    var names = root.querySelectorAll('[data-go]');
    // Load and decode every step's screen while the page is idle, so a click shows it at once.
    (window.requestIdleCallback || function (f) { setTimeout(f, 1200); })(function () {
      root.querySelectorAll('[data-stage] img').forEach(function (img) {
        img.loading = 'eager';
        if (img.decode) img.decode().catch(function () {});
      });
    });
    names.forEach(function (n) {
      n.addEventListener('click', function () {
        var i = +n.dataset.go;
        root.dataset.step = i;
        root.querySelectorAll('[data-stage]').forEach(function (el) { el.hidden = +el.dataset.stage !== i; });
        names.forEach(function (m, k) { if (k === i) m.setAttribute('aria-current', 'step'); else m.removeAttribute('aria-current'); });
      });
    });
  }

  function clock() {
    var d = new Date();
    var time = d.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' });
    var day = d.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' }).replace(',', '');
    document.querySelectorAll('.clock .d').forEach(function (c) { c.textContent = day; });
    document.querySelectorAll('.clock .t').forEach(function (c) { c.textContent = time; });
  }

  document.addEventListener('DOMContentLoaded', function () {
    fan(); walk(); clock(); setInterval(clock, 15000);
    var io = new IntersectionObserver(function (es) {
      es.forEach(function (e) { if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); } });
    }, { rootMargin: '0px 0px -8% 0px' });
    document.querySelectorAll('.rv').forEach(function (el) { io.observe(el); });
  });

  // A shared or clicked link such as /#portman lands on its section even after the images above it load.
  window.addEventListener('load', land);
  window.addEventListener('hashchange', land);
  function land() {
    var id = decodeURIComponent(location.hash.slice(1));
    var target = id && document.getElementById(id);
    if (!target) return;
    // Shown at once: a tile still mid-rise is 24 px low, and the scroll would land 24 px short.
    var shown = Array.prototype.slice.call(target.querySelectorAll('.rv'));
    if (target.classList.contains('rv')) shown.push(target);
    shown.forEach(function (el) { el.style.transition = 'none'; el.classList.add('in'); });
    target.scrollIntoView({ behavior: 'instant', block: 'start' });
    requestAnimationFrame(function () { shown.forEach(function (el) { el.style.transition = ''; }); });
  }
})();
