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

  function clamp(v, lo, hi) { return Math.min(Math.max(v, lo), hi); }

  // Portman: the section scrolls past a pinned screen; the scroll position picks the step.
  function story() {
    var root = document.querySelector('[data-pm]');
    if (!root) return;
    var vis = root.querySelector('.pm-vis'), cam = root.querySelector('.pm-cam'), mbi = cam.querySelector('.mbi');
    var pans = cam.querySelectorAll('.pm-pan'), win = cam.querySelector('.pm-win');
    var bars = root.querySelectorAll('[data-go]'), steps = root.querySelectorAll('.pm-step');
    var n = steps.length, step = -1, ticking = false;
    var calm = matchMedia('(prefers-reduced-motion: reduce)');
    (window.requestIdleCallback || function (f) { setTimeout(f, 1200); })(function () {
      cam.querySelectorAll('img').forEach(function (img) { img.loading = 'eager'; if (img.decode) img.decode().catch(function () {}); });
    });
    // The camera is the whole screen in macOS points at the window zoom; the panel zoom shows its top right corner.
    function size() {
      var w = vis.clientWidth, h = vis.clientHeight;
      var zp = clamp(h / 540, 0.7, 1.6), zw = clamp(h / 760, 0.45, 1.2), W = w / zw;
      cam.style.width = W + 'px'; cam.style.height = h / zw + 'px';
      root.style.setProperty('--zp', zp); root.style.setProperty('--zw', zw);
      var mid = mbi.offsetLeft + mbi.offsetWidth / 2, left = clamp(mid - 178, W - w / zp + 14, W - 356 - 14);
      pans.forEach(function (p) { p.style.left = left + 'px'; });
      // A narrow screen keeps the window bleeding off the right edge but never hides its "Portman" title on the left.
      win.style.left = Math.max(W - 820 - 24, -150) + 'px';
    }
    function paint() {
      ticking = false;
      var r = root.getBoundingClientRect(), span = r.height - innerHeight;
      var f = clamp(-r.top / span, 0, 1) * n, now = Math.min(n - 1, Math.floor(f));
      bars.forEach(function (b, i) { b.style.setProperty('--k', clamp(f - i, 0, 1)); });
      if (now === step) return;
      step = now; root.dataset.step = now;
      steps.forEach(function (s, i) { s.classList.toggle('on', i === now); s.classList.toggle('past', i < now); });
      bars.forEach(function (b, i) { if (i === now) b.setAttribute('aria-current', 'step'); else b.removeAttribute('aria-current'); });
    }
    function ask() { if (!ticking) { ticking = true; requestAnimationFrame(paint); } }
    bars.forEach(function (b, i) {
      b.addEventListener('click', function () {
        var top = root.getBoundingClientRect().top + scrollY, span = root.offsetHeight - innerHeight;
        scrollTo({ top: top + span * (i + 0.02) / n, behavior: calm.matches ? 'instant' : 'smooth' });
      });
    });
    new ResizeObserver(function () { size(); ask(); }).observe(vis);
    addEventListener('scroll', ask, { passive: true });
    size(); paint();
  }

  // GitHub: the live star count, once there are enough to show.
  function stars() {
    var out = document.querySelector('[data-stars]');
    if (!out || !window.fetch) return;
    fetch('https://api.github.com/repos/surajmandalcell/macpowertoys').then(function (r) { return r.ok ? r.json() : null; }).then(function (j) {
      var c = j && j.stargazers_count;
      if (c >= 25) out.textContent = c >= 1000 ? (c / 1000).toFixed(c < 10000 ? 1 : 0).replace(/\.0$/, '') + 'k' : String(c);
    }).catch(function () {});
  }

  // Download: the blue light follows the pointer, and the capsule leans a few points toward it.
  function glass() {
    if (matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    document.querySelectorAll('.glass').forEach(function (b) {
      function rest() { b.style.setProperty('--gx', b.offsetWidth / 2 + 'px'); b.style.setProperty('--gy', b.offsetHeight + 'px'); b.style.setProperty('--mx', '0px'); b.style.setProperty('--my', '0px'); }
      b.addEventListener('pointermove', function (e) {
        var r = b.getBoundingClientRect(), x = e.clientX - r.left, y = e.clientY - r.top;
        b.style.setProperty('--gx', x + 'px'); b.style.setProperty('--gy', y + 'px');
        b.style.setProperty('--mx', (x / r.width - 0.5) * 6 + 'px'); b.style.setProperty('--my', (y / r.height - 0.5) * 4 + 'px');
      });
      b.addEventListener('pointerleave', rest);
      rest();
    });
  }

  // Footer: the name in one letter per span, sized to fill the row; letters rise in, and hop under the pointer.
  function word() {
    var el = document.querySelector('[data-word]');
    if (!el) return;
    var text = el.dataset.word;
    el.textContent = '';
    text.split('').forEach(function (ch, k) { var s = document.createElement('span'); s.textContent = ch; s.style.setProperty('--k', k); el.appendChild(s); });
    function fit() {
      el.style.setProperty('--fs', '100px');
      var a = el.firstChild.offsetLeft, b = el.lastChild.offsetLeft + el.lastChild.offsetWidth;
      el.style.setProperty('--fs', 100 * el.clientWidth / (b - a) * 0.985 + 'px');
    }
    el.style.justifyContent = 'flex-start';
    fit(); el.style.justifyContent = '';
    new ResizeObserver(function () { el.style.justifyContent = 'flex-start'; fit(); el.style.justifyContent = ''; }).observe(el.parentNode);
    el.addEventListener('pointerover', function (e) {
      var s = e.target.closest('span');
      if (!s || s.classList.contains('up')) return;
      s.classList.add('up');
      setTimeout(function () { s.classList.remove('up'); }, 380);
    });
    new IntersectionObserver(function (es, o) { if (es[0].isIntersecting) { el.classList.add('in'); o.disconnect(); } }, { threshold: 0.2 }).observe(el);
  }

  function clock() {
    var d = new Date();
    var time = d.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' });
    var day = d.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' }).replace(',', '');
    // The Portman bar and both demo bars (inside their shadow roots) show the same time.
    var roots = [document].concat([].map.call(document.querySelectorAll('[data-demo]'), function (h) { return h.shadowRoot; }).filter(Boolean));
    roots.forEach(function (r) {
      r.querySelectorAll('.clock .d').forEach(function (c) { c.textContent = day; });
      r.querySelectorAll('.clock .t').forEach(function (c) { c.textContent = time; });
    });
  }

  document.addEventListener('DOMContentLoaded', function () {
    story(); stars(); glass(); word(); clock(); setInterval(clock, 15000);
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
