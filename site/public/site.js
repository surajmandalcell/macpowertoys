(function () {
  var calm = matchMedia('(prefers-reduced-motion: reduce)');
  var clamp = function (v, a, b) { return Math.min(b, Math.max(a, v)); };
  var lerp = function (a, b, t) { return a + (b - a) * t; };
  var smooth = function (t) { return t * t * (3 - 2 * t); };

  document.addEventListener('click', function (e) {
    var b = e.target.closest('[data-copy]');
    if (!b) return;
    if (navigator.clipboard) navigator.clipboard.writeText(b.getAttribute('data-copy')).catch(function () {});
    var box = b.closest('.brew,.cmd');
    box.classList.add('done');
    setTimeout(function () { box.classList.remove('done'); }, 1400);
  });

  // Film grain: one value per device pixel from a hash of the pixel position, never a repeating tile.
  // Four uniform samples make it roughly Gaussian; a 2 px value-noise layer adds clumps, like film.
  function grain() {
    var c = document.querySelector('.grain'), gl = c.getContext('webgl', { premultipliedAlpha: true, antialias: false });
    if (!gl) return grain2d(c);
    var vs = 'attribute vec2 p;void main(){gl_Position=vec4(p,0.,1.);}';
    var fs = 'precision highp float;' +
      'float h(vec2 p){vec3 q=fract(vec3(p.xyx)*.1031);q+=dot(q,q.yzx+33.33);return fract((q.x+q.y)*q.z);}' +
      'float v(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);' +
      'return mix(mix(h(i+91.),h(i+vec2(92.,91.)),f.x),mix(h(i+vec2(91.,92.)),h(i+92.),f.x),f.y);}' +
      'void main(){vec2 p=gl_FragCoord.xy;' +
      'float g=(h(p)+h(p+vec2(37.,17.))+h(p+vec2(-23.,59.))+h(p+vec2(71.,-41.))-2.)*1.73;' +
      'float n=.78*g+.9*(v(p/2.2)-.5);' +
      'float a=n>0.?n*.085:-n*.16;' +
      'gl_FragColor=n>0.?vec4(a,a,a,a):vec4(0.,0.,0.,a);}';
    function sh(type, src) { var s = gl.createShader(type); gl.shaderSource(s, src); gl.compileShader(s); return s; }
    var pr = gl.createProgram();
    gl.attachShader(pr, sh(gl.VERTEX_SHADER, vs)); gl.attachShader(pr, sh(gl.FRAGMENT_SHADER, fs));
    gl.linkProgram(pr); gl.useProgram(pr);
    gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
    var loc = gl.getAttribLocation(pr, 'p');
    gl.enableVertexAttribArray(loc); gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);
    function draw() {
      var d = devicePixelRatio || 1, w = Math.round(innerWidth * d), hh = Math.round(innerHeight * d);
      if (c.width === w && c.height === hh) return;
      c.width = w; c.height = hh;
      gl.viewport(0, 0, w, hh); gl.drawArrays(gl.TRIANGLES, 0, 3);
    }
    draw(); addEventListener('resize', draw);
  }
  function grain2d(c) {
    var x = c.getContext('2d');
    function draw() {
      var d = devicePixelRatio || 1, w = Math.round(innerWidth * d), h = Math.round(innerHeight * d);
      c.width = w; c.height = h;
      var img = x.createImageData(w, h), px = img.data;
      for (var i = 0; i < px.length; i += 4) {
        var n = (Math.random() + Math.random() + Math.random() + Math.random() - 2) * 1.73;
        var on = n > 0 ? 255 : 0;
        px[i] = px[i + 1] = px[i + 2] = on; px[i + 3] = Math.abs(n) * (n > 0 ? 22 : 40);
      }
      x.putImageData(img, 0, 0);
    }
    draw(); addEventListener('resize', draw);
  }

  // Scroll bar: a thin knob over a hidden native bar. It shows while scrolling or on hover and fades 1.8 s later.
  function scrollbar() {
    var bar = document.createElement('div'), knob = document.createElement('i'), timer, drag = null, kh = 0;
    bar.className = 'sb'; bar.setAttribute('aria-hidden', 'true'); bar.appendChild(knob); document.body.appendChild(bar);
    function room() { return document.documentElement.scrollHeight - innerHeight; }
    function place() {
      var r = room();
      kh = Math.max(88, innerHeight * innerHeight / (r + innerHeight));
      knob.style.height = kh + 'px';
      knob.style.transform = 'translateY(' + (r > 0 ? (innerHeight - kh) * scrollY / r : 0) + 'px)';
      bar.style.display = r > 0 ? '' : 'none';
    }
    function show() {
      bar.classList.add('on'); clearTimeout(timer);
      timer = setTimeout(function () { if (!drag) bar.classList.remove('on'); }, 1800);
    }
    addEventListener('scroll', function () { place(); show(); }, { passive: true });
    addEventListener('resize', place);
    new ResizeObserver(place).observe(document.body);
    bar.addEventListener('pointerdown', function (e) {
      e.preventDefault();
      var k = knob.getBoundingClientRect();
      if (e.clientY < k.top || e.clientY > k.bottom) scrollTo(0, (e.clientY - kh / 2) / (innerHeight - kh) * room());
      drag = { y: e.clientY, s: scrollY }; bar.classList.add('drag'); bar.setPointerCapture(e.pointerId);
    });
    bar.addEventListener('pointermove', function (e) {
      if (drag) scrollTo(0, drag.s + (e.clientY - drag.y) / (innerHeight - kh) * room());
    });
    bar.addEventListener('pointerup', function () { drag = null; bar.classList.remove('drag'); show(); });
    place();
  }



  function clock() {
    var d = new Date();
    var time = d.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' });
    var day = d.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' }).replace(',', '');
    var roots = [document].concat([].map.call(document.querySelectorAll('[data-demo]'), function (h) { return h.shadowRoot; }).filter(Boolean));
    roots.forEach(function (r) {
      r.querySelectorAll('.clock .d').forEach(function (c) { c.textContent = day; });
      r.querySelectorAll('.clock .t').forEach(function (c) { c.textContent = time; });
    });
  }


  document.addEventListener('DOMContentLoaded', function () {
    var zoom = function () { document.documentElement.style.setProperty('--z', Math.max(1, innerWidth / 1440)); };
    zoom(); addEventListener('resize', zoom);
    try { grain(); } catch (e) {}
    scrollbar();
    clock(); setInterval(clock, 15000); setTimeout(clock, 600);
  });
})();
