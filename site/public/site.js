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

  // Fan: the curve on the Fan page screenshot, with the app's own math (FanCurve.swift): a monotone cubic
  // through the points, and a safety floor from 0% at 90 °C to full speed at 95 °C.
  var CURVE = [[45, 0], [60, 0.22], [72, 0.5], [85, 1]], MIN_RPM = 1200, MAX_RPM = 4840;
  var TANGENTS = (function (p) {
    var s = p.slice(1).map(function (q, i) { return (q[1] - p[i][1]) / (q[0] - p[i][0]); });
    var m = [s[0]].concat(s.slice(1).map(function (v, i) { return s[i] * v <= 0 ? 0 : (s[i] + v) / 2; }), [s[s.length - 1]]);
    s.forEach(function (v, k) {
      if (!v) { m[k] = m[k + 1] = 0; return; }
      var a = m[k] / v, b = m[k + 1] / v, l = a * a + b * b;
      if (l > 9) { var q = 3 / Math.sqrt(l); m[k] = q * a * v; m[k + 1] = q * b * v; }
    });
    return m;
  })(CURVE);
  function curveSpeed(c) {
    var first = CURVE[0], last = CURVE[CURVE.length - 1];
    if (c <= first[0]) return first[1];
    if (c >= last[0]) return last[1];
    var u = CURVE.findIndex(function (p) { return p[0] >= c; }), k = u - 1;
    var lo = CURVE[k], hi = CURVE[u], w = hi[0] - lo[0], t = (c - lo[0]) / w, t2 = t * t, t3 = t2 * t;
    var v = (2 * t3 - 3 * t2 + 1) * lo[1] + (t3 - 2 * t2 + t) * w * TANGENTS[k]
      + (-2 * t3 + 3 * t2) * hi[1] + (t3 - t2) * w * TANGENTS[u];
    return Math.min(Math.max(v, lo[1]), hi[1]);
  }
  function fanSpeed(c) { return Math.max(curveSpeed(c), Math.min(Math.max((c - 90) / 5, 0), 1)); }
  // CPUHeat.swift: the word and color step for each temperature.
  function heat(c) { return c < 56 ? 'normal' : c < 70 ? 'warm' : c < 85 ? 'hot' : c < 95 ? 'very hot' : 'near the limit'; }

  function fan() {
    var root = document.querySelector('[data-fan]');
    if (!root) return;
    var $ = function (id) { return document.getElementById(id); };
    var input = $('heat'), rpmOut = $('fan-rpm'), tempOut = $('fan-temp'), wordOut = $('fan-word');
    var dot = $('fan-dot'), guide = $('fan-guide'), blades = root.querySelector('.blades');
    var X = function (c) { return (c - 30) / 70 * 320; }, Y = function (s) { return 120 - s * 112; };
    var d = '';
    for (var c = 30; c <= 100; c += 0.5) d += (c === 30 ? 'M' : 'L') + X(c).toFixed(1) + ' ' + Y(curveSpeed(c)).toFixed(1);
    $('fan-line').setAttribute('d', d);
    $('fan-area').setAttribute('d', d + 'L320 120L0 120Z');

    var calm = matchMedia('(prefers-reduced-motion: reduce)');
    var target = +input.value, shown = target, angle = 0, last = 0, raf = 0, visible = false, demo = [], auto = false;
    function paint() {
      var c = shown, s = fanSpeed(c), rounded = Math.round(c), word = heat(rounded);
      var rpm = Math.round((MIN_RPM + s * (MAX_RPM - MIN_RPM)) / 10) * 10;
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
      var s = paint();
      // About 0.4 turns a second at the slowest and 3.4 at full speed.
      angle = (angle + dt * (0.4 + s * 3) * 360) % 360;
      blades.style.transform = 'rotate(' + angle + 'deg)';
      raf = visible && !calm.matches ? requestAnimationFrame(frame) : 0;
    }
    function wake() { if (!raf && visible && !calm.matches) { last = 0; raf = requestAnimationFrame(frame); } }
    function stopDemo() { demo.forEach(clearTimeout); demo = []; auto = false; }
    input.addEventListener('input', function () {
      stopDemo();
      target = +input.value;
      if (calm.matches) { shown = target; paint(); } else wake();
    });
    new IntersectionObserver(function (es) {
      visible = es[0].isIntersecting;
      if (!visible) return;
      wake();
      // The first time it shows, sweep once from cool to hot and back, unless someone already touched it.
      if (!calm.matches && !root.dataset.played) {
        root.dataset.played = "1"; auto = true;
        demo = [[500, 92], [2600, 48], [4300, 62]].map(function (step) {
          return setTimeout(function () { target = step[1]; }, step[0]);
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
