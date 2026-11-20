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

  // Fan: the app's standard Cool curve runs from slowest at 65 °C to full speed at 90 °C.
  function fan() {
    var input = document.getElementById('heat');
    if (!input) return;
    var out = document.getElementById('heat-out'), bar = document.getElementById('heat-bar');
    function update() {
      var c = +input.value;
      var speed = Math.min(Math.max((c - 65) / 25, 0), 1);
      var pct = Math.round(speed * 100);
      out.textContent = pct === 0 ? 'At ' + c + ' °C the fans stay at their slowest.'
        : pct === 100 ? 'At ' + c + ' °C the fans run at full speed.'
        : 'At ' + c + ' °C the fans run at ' + pct + '% of their range.';
      bar.style.width = Math.max(pct, 2) + '%';
      input.setAttribute('aria-valuetext', c + ' °C');
    }
    input.addEventListener('input', update);
    update();
  }

  // Portman: four step buttons switch what the screen shows.
  function walk() {
    var root = document.querySelector('[data-walk]');
    if (!root) return;
    var names = root.querySelectorAll('[data-go]');
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

  // A shared link such as /#portman lands on its section even after the images above it load.
  window.addEventListener('load', function () {
    var id = decodeURIComponent(location.hash.slice(1));
    var target = id && document.getElementById(id);
    if (!target) return;
    target.querySelectorAll('.rv').forEach(function (el) { el.classList.add('in'); });
    if (target.classList.contains('rv')) target.classList.add('in');
    target.scrollIntoView({ behavior: 'instant', block: 'start' });
  });
})();
