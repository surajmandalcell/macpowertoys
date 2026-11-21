(function () {
  var doc = document.documentElement;
  function flash(el) {
    el.classList.add('done');
    setTimeout(function () { el.classList.remove('done'); }, 1400);
  }
  function copy(text) {
    if (navigator.clipboard) navigator.clipboard.writeText(text).catch(function () {});
  }
  function store(k, v) { try { localStorage.setItem('mpt-' + k, v); } catch (e) {} }

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
  var calm = matchMedia('(prefers-reduced-motion: reduce)');
  function still() { return calm.matches || doc.dataset.motion === 'off'; }
  var CURSOR = '<svg viewBox="0 0 20 28"><path d="M2.5 2.5v20l5-4.6 3.2 7.4 3.4-1.4-3.2-7.3h6.6z" fill="#000" stroke="#fff" stroke-width="1.6" stroke-linejoin="round"/></svg>';

  // Where a step sits on the page: its chapter's top plus its share of the pinned scroll.
  function stepTop(root, i, n) {
    return root.getBoundingClientRect().top + scrollY + (root.offsetHeight - innerHeight) * (i + 0.02) / n;
  }

  // A tool story: the chapter scrolls past a pinned screen, and the scroll position picks the step.
  // Each step names a shot, and may add a spotlight ("x y w h" in shot points) or a click on its menu bar icon.
  function story(root) {
    var vis = root.querySelector('.s-vis'), cam = root.querySelector('.s-cam');
    cam.prepend(document.getElementById('mbar').content.cloneNode(true));
    var shots = [].slice.call(cam.querySelectorAll('.shot')), steps = [].slice.call(root.querySelectorAll('.st'));
    var n = steps.length, ol = root.querySelector('.bars'), icons = {}, geo = [], step = -1, ticking = false, timers = [], pending = false, seen = false;
    root.style.setProperty('--n', n);
    if (n < 2) root.classList.add('one');
    steps.forEach(function (s, i) {
      var li = document.createElement('li'), b = document.createElement('button');
      b.type = 'button'; b.setAttribute('aria-label', 'Step ' + (i + 1) + ': ' + s.querySelector('h3').textContent);
      b.appendChild(document.createElement('i')); li.appendChild(b); ol.appendChild(li);
      b.addEventListener('click', function () { scrollTo({ top: stepTop(root, i, n), behavior: calm.matches ? 'instant' : 'smooth' }); });
    });
    var bars = [].slice.call(ol.querySelectorAll('button'));
    var spot = document.createElement('i'), cur = document.createElement('i');
    spot.className = 'spot'; cur.className = 'cur'; cur.innerHTML = CURSOR;
    cam.append(spot, cur);
    cam.querySelectorAll('.ico').forEach(function (e) { icons[e.dataset.ico] = e; });
    (window.requestIdleCallback || function (f) { setTimeout(f, 1200); })(function () {
      cam.querySelectorAll('img').forEach(function (img) { img.loading = 'eager'; if (img.decode) img.decode().catch(function () {}); });
    });

    // The camera is the whole screen in macOS points at the smallest zoom; each shot has its own zoom,
    // and the camera scales from its top right corner, so a panel shows under its menu bar icon.
    function size() {
      var w = vis.clientWidth, h = vis.clientHeight;
      var zs = shots.map(function (s) {
        var sh = +s.querySelector('img').getAttribute('height');
        return s.classList.contains('pan') ? clamp(h / 540, 0.7, 1.6) : clamp(h / (sh + 100), 0.45, 1.2);
      });
      var zmin = Math.min.apply(null, zs), W = w / zmin;
      cam.style.width = W + 'px'; cam.style.height = h / zmin + 'px';
      shots.forEach(function (s, i) {
        var img = s.querySelector('img'), sw = +img.getAttribute('width'), sh = +img.getAttribute('height');
        var z = zs[i], vw = w / z, vh = h / z, x, y;
        if (s.classList.contains('pan')) {
          var ic = icons[s.dataset.ico];
          x = clamp(ic.offsetLeft + ic.offsetWidth / 2 - sw / 2, W - vw + 14, W - sw - 14); y = 29;
        } else {
          // A window that fits sits in the middle; a wider one runs off the left edge, keeping its sidebar.
          x = sw + 48 <= vw ? W - (vw + sw) / 2 : Math.max(W - sw - 24, W - vw - 150);
          y = Math.max(40, (vh - sh) / 2 + 12);
        }
        s.style.width = sw + 'px'; s.style.left = x + 'px'; s.style.top = y + 'px';
        geo[i] = { x: x, y: y, z: z };
      });
      if (step >= 0) place();
    }
    function iconPoint(ic) { return [ic.offsetLeft + ic.offsetWidth / 2 - 4, 9]; }
    function moveCursor(p) { cur.style.transform = 'translate(' + p[0] + 'px,' + p[1] + 'px)'; }
    function place() {
      var st = steps[step], g = geo[+st.dataset.shot], sp = st.dataset.spot;
      cam.style.setProperty('--z', g.z);
      if (sp) {
        var r = sp.split(' ').map(Number);
        spot.style.width = r[2] + 'px'; spot.style.height = r[3] + 'px';
        spot.style.transform = 'translate(' + (g.x + r[0]) + 'px,' + (g.y + r[1]) + 'px)';
      }
    }
    function open(si) {
      var ic = icons[shots[si].dataset.ico];
      shots.forEach(function (s, i) { s.classList.toggle('on', i === si); });
      Object.keys(icons).forEach(function (k) { icons[k].classList.toggle('on', icons[k] === ic); });
      spot.classList.toggle('on', !!steps[step].dataset.spot);
    }
    // The pointer comes in from below, clicks the icon, and the panel opens under it.
    function click() {
      pending = false;
      var st = steps[step], si = +st.dataset.shot, ic = icons[shots[si].dataset.ico], end = iconPoint(ic);
      if (still()) { moveCursor(end); cur.classList.add('on'); open(si); return; }
      cur.style.transition = 'none'; moveCursor([end[0] - 150, 230]); cur.getBoundingClientRect(); cur.style.transition = '';
      cur.classList.add('on');
      timers.push(setTimeout(function () { moveCursor(end); }, 60));
      timers.push(setTimeout(function () { cur.classList.add('down'); }, 1100));
      timers.push(setTimeout(function () { cur.classList.remove('down'); open(si); }, 1230));
    }
    function show(prev) {
      var st = steps[step], si = +st.dataset.shot;
      steps.forEach(function (s, i) { s.classList.toggle('on', i === step); s.classList.toggle('past', i < step); });
      bars.forEach(function (b, i) { if (i === step) b.setAttribute('aria-current', 'step'); else b.removeAttribute('aria-current'); });
      timers.forEach(clearTimeout); timers = [];
      place();
      if (st.hasAttribute('data-click') && prev < step) {
        shots.forEach(function (s) { s.classList.remove('on'); });
        Object.keys(icons).forEach(function (k) { icons[k].classList.remove('on'); });
        spot.classList.remove('on');
        pending = true; if (seen) click();
        return;
      }
      cur.classList.toggle('on', st.hasAttribute('data-click'));
      open(si);
    }
    function paint() {
      ticking = false;
      var f = 0;
      if (n > 1) { var r = root.getBoundingClientRect(); f = clamp(-r.top / (r.height - innerHeight), 0, 1) * n; }
      var now = Math.min(n - 1, Math.floor(f));
      bars.forEach(function (b, i) { b.style.setProperty('--k', clamp(f - i, 0, 1)); });
      if (now === step) return;
      var prev = step; step = now; show(prev);
    }
    function ask() { if (!ticking) { ticking = true; requestAnimationFrame(paint); } }
    // The click plays once the screen is in view, not while it is still below the fold.
    new IntersectionObserver(function (es) { seen = es[0].isIntersecting; if (seen && pending) click(); }, { threshold: 0.5 }).observe(vis);
    new ResizeObserver(size).observe(vis);
    addEventListener('scroll', ask, { passive: true });
    size(); paint();
  }

  // Backgrounds: one sticky screen of layers per chapter; only chapters on screen animate.
  function backgrounds() {
    var io = new IntersectionObserver(function (es) { es.forEach(function (e) { e.target.classList.toggle('live', e.isIntersecting); }); });
    document.querySelectorAll('.ch').forEach(function (ch) {
      var bg = document.createElement('div'), v = document.createElement('div');
      bg.className = 'bg'; bg.setAttribute('aria-hidden', 'true'); v.className = 'v';
      ['l-w', 'l-a', 'l-b', 'l-c', 'l-s', 'l-g'].forEach(function (c) { var i = document.createElement('i'); i.className = c; v.appendChild(i); });
      if (ch.dataset.bgWall) bg.style.setProperty('--wall', 'url(assets/bg/' + ch.dataset.bgWall + '.webp)');
      bg.appendChild(v); ch.prepend(bg); io.observe(ch);
    });
  }

  // Dock: the background style and the animation, both remembered; Copy choices copies the picks.
  function dock() {
    var d = document.querySelector('.dock');
    if (!d) return;
    function sync() {
      d.querySelectorAll('.seg').forEach(function (s) {
        var cur = doc.dataset[s.dataset.set];
        s.querySelectorAll('button').forEach(function (b) { b.setAttribute('aria-pressed', b.dataset.val === cur); });
      });
    }
    d.addEventListener('click', function (e) {
      var b = e.target.closest('button');
      if (!b) return;
      if (b.hasAttribute('data-choices')) {
        var bg = d.querySelector('[data-set=bg] [aria-pressed=true]'), all = [].slice.call(d.querySelectorAll('[data-set=bg] button'));
        copy('- Background: ' + (all.indexOf(bg) + 1) + ' ' + bg.textContent + '\n- Animation: ' + d.querySelector('[data-set=motion] [aria-pressed=true]').dataset.val.replace(/^./, function (c) { return c.toUpperCase(); }));
        flash(b); return;
      }
      var set = b.parentNode.dataset.set;
      doc.dataset[set] = b.dataset.val; store(set, b.dataset.val); sync();
    });
    sync();
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
    if (calm.matches) return;
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
    // Every story bar and both demo bars (inside their shadow roots) show the same time.
    var roots = [document].concat([].map.call(document.querySelectorAll('[data-demo]'), function (h) { return h.shadowRoot; }).filter(Boolean));
    roots.forEach(function (r) {
      r.querySelectorAll('.clock .d').forEach(function (c) { c.textContent = day; });
      r.querySelectorAll('.clock .t').forEach(function (c) { c.textContent = time; });
    });
  }

  document.addEventListener('DOMContentLoaded', function () {
    backgrounds();
    document.querySelectorAll('[data-story]').forEach(story);
    dock(); stars(); glass(); word(); clock(); setInterval(clock, 15000);
    var io = new IntersectionObserver(function (es) {
      es.forEach(function (e) { if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); } });
    }, { rootMargin: '0px 0px -8% 0px' });
    document.querySelectorAll('.rv').forEach(function (el) { io.observe(el); });
  });

  // A shared or clicked link such as /#portman or /#ruler lands on its chapter or story step,
  // even after the images above it load.
  window.addEventListener('load', land);
  window.addEventListener('hashchange', land);
  function land() {
    var id = decodeURIComponent(location.hash.slice(1));
    var target = id && document.getElementById(id);
    if (!target) return;
    if (target.classList.contains('st')) {
      var root = target.closest('[data-story]'), all = [].slice.call(root.querySelectorAll('.st'));
      scrollTo({ top: stepTop(root, all.indexOf(target), all.length), behavior: 'instant' });
      return;
    }
    // Shown at once: a part still mid-rise is 24 px low, and the scroll would land 24 px short.
    var shown = Array.prototype.slice.call(target.querySelectorAll('.rv'));
    if (target.classList.contains('rv')) shown.push(target);
    shown.forEach(function (el) { el.style.transition = 'none'; el.classList.add('in'); });
    target.scrollIntoView({ behavior: 'instant', block: 'start' });
    requestAnimationFrame(function () { shown.forEach(function (el) { el.style.transition = ''; }); });
  }
})();
