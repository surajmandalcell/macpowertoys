(function () {
  var theme = new URLSearchParams(location.search).get('theme');
  if (theme === 'light' || theme === 'dark') document.documentElement.setAttribute('data-theme', theme);

  function flash(el) {
    el.classList.add('done');
    setTimeout(function () { el.classList.remove('done'); }, 1400);
  }
  function copy(text) {
    if (navigator.clipboard) navigator.clipboard.writeText(text).catch(function () {});
  }

  document.addEventListener('click', function (e) {
    var b = e.target.closest('[data-copy]');
    if (b) { copy(b.getAttribute('data-copy')); flash(b); return; }
    var a = e.target.closest('.anchor');
    if (a) {
      e.preventDefault();
      var hash = a.getAttribute('href');
      history.replaceState(null, '', hash);
      copy(location.origin + location.pathname + hash);
      flash(a);
    }
  });

  document.addEventListener('DOMContentLoaded', function () {
    var io = new IntersectionObserver(function (es) {
      es.forEach(function (e) { if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); } });
    }, { rootMargin: '0px 0px -8% 0px' });
    document.querySelectorAll('.rv').forEach(function (el) { io.observe(el); });

    function tick() {
      var d = new Date();
      var s = d.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' }) + '  ' +
        d.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' });
      document.querySelectorAll('.clock').forEach(function (c) { c.textContent = s; });
    }
    tick(); setInterval(tick, 10000);
  });

  // A shared link such as /#portman lands on its section even after images above it load.
  window.addEventListener('load', function () {
    var id = decodeURIComponent(location.hash.slice(1));
    var target = id && document.getElementById(id);
    if (!target) return;
    target.querySelectorAll('.rv').forEach(function (el) { el.classList.add('in'); });
    target.scrollIntoView({ behavior: 'instant', block: 'start' });
  });
})();
