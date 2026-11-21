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

  // Every step is one screen of scroll with its own snap point, so each scroll gesture moves one step.
  function stepTop(root, i) { return root.getBoundingClientRect().top + scrollY + i * innerHeight; }

  // A tool story: the screen stays pinned while the page snaps from step to step.
  // Each step names a shot, and may add a spotlight ("x y w h" in shot points) or a click on its menu bar icon.
  function story(root) {
    var vis = root.querySelector('.s-vis'), cam = root.querySelector('.s-cam');
    cam.prepend(document.getElementById('mbar').content.cloneNode(true));
    var shots = [].slice.call(cam.querySelectorAll('.shot')), steps = [].slice.call(root.querySelectorAll('.st'));
    var n = steps.length, ol = root.querySelector('.bars'), icons = {}, geo = [], step = -1, ticking = false, timers = [], pending = false, seen = false;
    root.style.setProperty('--n', n);
    if (n < 2) root.classList.add('one');
    steps.forEach(function (s, i) {
      var li = document.createElement('li'), b = document.createElement('button'), mark = document.createElement('i');
      mark.className = 'snap'; mark.style.top = i * 100 + 'svh'; root.appendChild(mark);
      b.type = 'button'; b.setAttribute('aria-label', 'Step ' + (i + 1) + ': ' + s.querySelector('h3').textContent);
      b.appendChild(document.createElement('i')); li.appendChild(b); ol.appendChild(li);
      b.addEventListener('click', function () { scrollTo({ top: stepTop(root, i), behavior: calm.matches ? 'instant' : 'smooth' }); });
    });
    var bars = [].slice.call(ol.querySelectorAll('button'));
    var spot = document.createElement('i'), cur = document.createElement('i');
    spot.className = 'spot'; cur.className = 'cur'; cur.innerHTML = CURSOR;
    cam.append(spot, cur);
    cam.querySelectorAll('.ico').forEach(function (e) { icons[e.dataset.ico] = e; });

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
      // The whole click takes about 400 ms, so the panel opens before the empty desktop reads as a pause.
      cur.style.transition = 'none'; moveCursor([end[0] - 60, 110]); cur.getBoundingClientRect(); cur.style.transition = '';
      cur.classList.add('on');
      timers.push(setTimeout(function () { moveCursor(end); }, 20));
      timers.push(setTimeout(function () { cur.classList.add('down'); }, 320));
      timers.push(setTimeout(function () { cur.classList.remove('down'); open(si); }, 400));
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
      var top = root.getBoundingClientRect().top, f = clamp(-top / innerHeight, 0, n - 1);
      var now = Math.round(f);
      bars.forEach(function (b, i) { b.style.setProperty('--k', clamp(f - i + 1, 0, 1)); });
      // The click plays once the story has mostly snapped in, not while it is still fading in.
      var was = seen; seen = top < innerHeight * 0.35 && top > -root.offsetHeight + innerHeight * 0.65;
      if (seen && !was && pending) click();
      if (now === step) return;
      var prev = step; step = now; show(prev);
    }
    function ask() { if (!ticking) { ticking = true; requestAnimationFrame(paint); } }
    new ResizeObserver(size).observe(vis);
    addEventListener('scroll', ask, { passive: true });
    size(); paint();
  }

  // Chapters: each screen is a fixed layer and the scroll picks the one to show. On a switch the two
  // screens crossfade while the old main box flies into the new one's place and the new one grows out
  // of its anchor (data-from: a part of either screen, "host>>>part" inside a demo), so it reads as one
  // thing turning into the next. Going back plays the same morph in reverse. Web Animations only.
  var MAIN = '.hero-demo,.fan-demo,.s-vis,.list,.install';
  function chapters() {
    var chs = [].slice.call(document.querySelectorAll('.ch')), cur = -1, runs = [], ticking = false;
    var scr = chs.map(function (c) { var s = c.querySelector('.s-pin') || c.querySelector('.stage'); s.classList.add('scr'); return s; });
    var last = scr[scr.length - 1];
    function anchor(c) {
      var p = (c.dataset.from || '').split('>>>'), el = p[0] && document.querySelector(p[0]);
      return el && p[1] ? el.shadowRoot && el.shadowRoot.querySelector(p[1]) : el;
    }
    function fly(a, b) { return 'translate(' + (b.left - a.left) + 'px,' + (b.top - a.top) + 'px) scale(' + b.width / a.width + ',' + b.height / a.height + ')'; }
    function go(i) {
      var j = cur; cur = i;
      runs.forEach(function (r) { r.cancel(); }); runs = [];
      scr.forEach(function (s, k) { s.classList.toggle('on', k === i || k === j); });
      function settle() { scr.forEach(function (s, k) { s.classList.toggle('on', k === cur); }); }
      if (j < 0 || doc.dataset.motion === 'off') return settle();
      var lo = Math.min(i, j), hi = Math.max(i, j), back = i < j;
      var ma = scr[lo].querySelector(MAIN), mb = scr[hi].querySelector(MAIN), an = anchor(chs[hi]);
      var ra = ma.getBoundingClientRect(), rb = mb.getBoundingClientRect(), rs = an ? an.getBoundingClientRect() : ra;
      var ms = calm.matches ? 240 : 480, ease = 'cubic-bezier(.3,.7,.15,1)';
      function play(el, frames) { if (back) frames.reverse(); runs.push(el.animate(frames, { duration: ms, easing: ease })); }
      play(scr[lo], [{ opacity: 1 }, { opacity: 0 }]);
      play(scr[hi], [{ opacity: 0 }, { opacity: 1 }]);
      if (!calm.matches && ra.width && rb.width && rs.width) {
        play(ma, [{ transformOrigin: '0 0', transform: 'none' }, { transformOrigin: '0 0', transform: fly(ra, rb) }]);
        play(mb, [{ transformOrigin: '0 0', transform: fly(rb, rs) }, { transformOrigin: '0 0', transform: 'none' }]);
      }
      runs[0].onfinish = settle;
    }
    function paint() {
      ticking = false;
      var y = innerHeight * 0.5, i = 0;
      while (i < chs.length - 1 && chs[i + 1].getBoundingClientRect().top <= y) i++;
      // Past the last chapter the footer scrolls in, and the last screen moves up with it.
      var over = Math.max(0, -chs[chs.length - 1].getBoundingClientRect().top);
      last.style.translate = over ? '0 ' + -over + 'px' : '';
      if (i !== cur) { go(i); warm(i); }
    }
    // Decode this screen's and the next two screens' images while idle, so a first visit does not
    // decode them in the frame that shows them. Kept close to use, so the decode cache still holds them.
    function warm(i) {
      (window.requestIdleCallback || function (f) { setTimeout(f, 200); })(function () {
        scr.slice(Math.max(0, i - 1), i + 3).forEach(function (s) {
          s.querySelectorAll('img').forEach(function (img) { img.loading = 'eager'; if (img.decode) img.decode().catch(function () {}); });
        });
      });
    }
    addEventListener('scroll', function () { if (!ticking) { ticking = true; requestAnimationFrame(paint); } }, { passive: true });
    addEventListener('resize', paint);
    paint();
  }

  // The background: the "Fractal Maze" wallpaper turned upright and drawn live. Blurred orbs sit behind
  // fluted glass; each glass rib shifts and squeezes what is behind it and has a lit top edge.
  // One fixed canvas for the whole page. Orbs drift slower than the scroll and move to a new
  // arrangement of the same colors at each chapter. Grain is a CSS layer at full resolution.
  // Orb colors: off-white, teal, coral, orange, hot pink, off-white, deep teal.
  var ORB_RGB = [[.86, .85, .84], [.17, .33, .36], [.84, .37, .27], [.87, .43, .2], [.92, .1, .38], [.78, .77, .76], [.07, .19, .21]];
  // Per chapter: x and y as a share of the screen, radius as a share of its height, and strength.
  var SCENES = [
    [[.88, .1, .2, .75], [.7, .55, .26, .7], [.64, .4, .3, .8], [.84, .8, .34, .8], [.42, .94, .16, .85], [.99, .96, .18, .5], [.12, .5, .42, .9]],
    [[.1, .96, .2, .6], [.25, .15, .3, .7], [.55, .62, .36, .8], [.86, .36, .3, .8], [.16, .62, .18, .8], [.96, .04, .16, .5], [.5, .1, .35, .8]],
    [[.15, .15, .22, .7], [.76, .3, .3, .8], [.35, .6, .32, .8], [.1, .86, .3, .75], [.45, .96, .15, .8], [.02, .5, .18, .5], [.86, .74, .36, .9]],
    [[.3, .9, .2, .6], [.2, .25, .34, .85], [.05, .55, .28, .7], [.45, .35, .22, .6], [.6, .98, .14, .7], [.1, .05, .16, .5], [.8, .4, .4, .9]],
    [[.05, .3, .2, .65], [.4, .86, .3, .75], [.35, .2, .3, .85], [.15, .7, .3, .85], [.55, .5, .14, .75], [.45, 1, .18, .5], [.85, .2, .38, .9]],
    [[.4, .05, .2, .6], [.1, .6, .3, .7], [.2, .9, .3, .8], [.5, .65, .26, .7], [.3, .3, .18, .9], [0, 0, .18, .5], [.85, .6, .4, .9]],
    [[.2, .6, .22, .65], [.45, .15, .3, .8], [.1, .25, .3, .75], [.4, .9, .32, .8], [.05, .85, .16, .85], [.55, .45, .15, .45], [.85, .4, .4, .9]],
    [[.9, .9, .22, .6], [.2, .7, .3, .7], [.76, .3, .3, .75], [.96, .6, .3, .7], [.6, .96, .15, .8], [1, .1, .18, .5], [.15, .25, .4, .9]],
    [[.5, 1.1, .25, .55], [.1, .2, .3, .6], [.2, .96, .3, .7], [.86, .96, .3, .7], [.96, .3, .14, .6], [0, .6, .16, .4], [.5, .4, .45, .9]]
  ];
  var FRAG = [
    'precision mediump float;',
    'uniform vec2 R;uniform float P;uniform vec4 O[7];uniform vec3 C[7];',
    'vec3 scene(vec2 q){vec2 p=q/R.y;float a=R.x/R.y;vec3 c=vec3(.03,.032,.036);',
    ' for(int i=0;i<7;i++){vec2 d=p-vec2(O[i].x*a,O[i].y);float e=dot(d,d)/(O[i].z*O[i].z);c=mix(c,C[i],O[i].w*exp(-1.3*e*e));}',
    ' return c;}',
    'float h(float k){return fract(sin(k*91.7)*4375.85);}',
    'void main(){vec2 q=vec2(gl_FragCoord.x,R.y-gl_FragCoord.y);',
    // Ribs run across the screen (the wallpaper's upright ribs, turned with it) and vary a little in width.
    ' float y=q.y/P;y+=.22*sin(y*1.37);float k=floor(y),t=fract(y),r=h(k);',
    ' vec2 s=vec2(q.x*(1.+(r-.5)*.05)+(r-.5)*R.x*.012,q.y+(.5-t)*P*.5+(r-.5)*P*.6);',
    ' vec3 c=scene(s);',
    ' c*=1.-.15*smoothstep(.8,1.,t);c+=.05*(1.-smoothstep(0.,.1,t))*(.4+c);',
    ' vec2 v=gl_FragCoord.xy/R-.5;c*=.84-.4*dot(v,v);',
    ' gl_FragColor=vec4(c,1.);}'
  ].join('\n');
  function background() {
    var cv = document.createElement('canvas'), gl;
    cv.className = 'bgc'; cv.setAttribute('aria-hidden', 'true');
    document.body.prepend(cv);
    var grain = document.createElement('i'); grain.className = 'grain'; grain.setAttribute('aria-hidden', 'true');
    document.body.prepend(grain);
    try { gl = cv.getContext('webgl', { antialias: false, alpha: false, powerPreference: 'low-power' }); } catch (e) {}
    function sh(type, src) { var s = gl.createShader(type); gl.shaderSource(s, src); gl.compileShader(s); return s; }
    var pr = gl && gl.createProgram();
    if (pr) {
      gl.attachShader(pr, sh(gl.VERTEX_SHADER, 'attribute vec2 v;void main(){gl_Position=vec4(v,0.,1.);}'));
      gl.attachShader(pr, sh(gl.FRAGMENT_SHADER, FRAG));
      gl.linkProgram(pr);
    }
    if (!pr || !gl.getProgramParameter(pr, gl.LINK_STATUS)) { doc.classList.add('nogl'); cv.remove(); return; }
    gl.useProgram(pr);
    gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
    gl.enableVertexAttribArray(0); gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);
    var uR = gl.getUniformLocation(pr, 'R'), uP = gl.getUniformLocation(pr, 'P'), uO = gl.getUniformLocation(pr, 'O'), uC = gl.getUniformLocation(pr, 'C');
    gl.uniform3fv(uC, new Float32Array([].concat.apply([], ORB_RGB)));
    var chs = [].slice.call(document.querySelectorAll('.ch')), tops = [], orbs = new Float32Array(28), t0 = performance.now(), last = -1, raf = 0;
    // Blurred orbs need few pixels: half the CSS size on every screen, whatever its pixel density.
    var SCALE = 0.5;
    function resize() {
      cv.width = Math.round(innerWidth * SCALE); cv.height = Math.round(innerHeight * SCALE);
      gl.viewport(0, 0, cv.width, cv.height);
      gl.uniform2f(uR, cv.width, cv.height);
      gl.uniform1f(uP, 0.038 * Math.max(innerWidth, innerHeight) * SCALE);
      tops = chs.map(function (c) { return c.getBoundingClientRect().top + scrollY; });
      last = -1; draw();
    }
    function ease(x) { x = clamp(x, 0, 1); return x * x * (3 - 2 * x); }
    function draw() {
      raf = 0;
      var y = scrollY, vh = innerHeight, i = 0, time = doc.dataset.motion === 'play' && !calm.matches ? (performance.now() - t0) / 1000 : 0;
      while (i < tops.length - 1 && tops[i + 1] <= y) i++;
      var j = Math.min(i + 1, tops.length - 1), m = j > i ? ease((y - (tops[j] - vh)) / vh) : 0;
      var a = SCENES[i % SCENES.length], b = SCENES[j % SCENES.length];
      // Parallax: the orbs move up at a twentieth of the scroll within a chapter.
      var da = -0.05 * (y - tops[i]) / vh, db = -0.05 * (y - tops[j]) / vh;
      for (var k = 0; k < 7; k++) {
        var wx = 0.02 * Math.sin(time * 0.11 + k * 1.3), wy = 0.02 * Math.cos(time * 0.08 + k * 2.1);
        orbs[k * 4] = a[k][0] + (b[k][0] - a[k][0]) * m + wx;
        orbs[k * 4 + 1] = a[k][1] + da + (b[k][1] + db - a[k][1] - da) * m + wy;
        orbs[k * 4 + 2] = a[k][2] + (b[k][2] - a[k][2]) * m;
        orbs[k * 4 + 3] = a[k][3] + (b[k][3] - a[k][3]) * m;
      }
      gl.uniform4fv(uO, orbs);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
      if (time) ask();
    }
    function ask() { if (!raf && !document.hidden) raf = requestAnimationFrame(draw); }
    addEventListener('scroll', ask, { passive: true });
    addEventListener('resize', resize);
    document.addEventListener('visibilitychange', ask);
    new ResizeObserver(resize).observe(document.body);
    new MutationObserver(ask).observe(doc, { attributes: true, attributeFilter: ['data-motion'] });
    resize();
  }

  // Dock: the tool card style and the animation, both remembered; Copy choices copies the picks.
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
        var cd = d.querySelector('[data-set=card] [aria-pressed=true]'), all = [].slice.call(d.querySelectorAll('[data-set=card] button'));
        copy('- Tool card: ' + (all.indexOf(cd) + 1) + ' ' + cd.textContent + '\n- Animation: ' + d.querySelector('[data-set=motion] [aria-pressed=true]').dataset.val.replace(/^./, function (c) { return c.toUpperCase(); }));
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
    document.querySelectorAll('[data-story]').forEach(story);
    chapters();
    background();
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
      scrollTo({ top: stepTop(root, all.indexOf(target)), behavior: 'instant' });
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
