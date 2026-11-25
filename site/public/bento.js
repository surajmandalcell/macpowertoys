// The final bento: static tiles. Screenshot tiles show a real capture whose window top-left sits under the text and
// bleeds off the right and bottom edges; icon tiles show only the icon and the line. No click, no video, no motion.
document.addEventListener('DOMContentLoaded', function () {
  var IC = 'assets/tools/', CAP = 'assets/captures/';
  var TOOLS = {
    fan: ['Fan', 'fan.webp', 'Curves that keep your Mac quiet.', 'fan'],
    portman: ['Portman', 'portman.webp', 'Dev servers and SSH ports, one list.', 'portman'],
    rsync: ['RSync UI', 'rsync.webp', 'Cloud copies that pause and resume.', 'rsync'],
    tweaks: ['Mac Tweaks', 'mac-tweaks.webp', 'Hidden macOS settings, one switch away.', 'mac-tweaks'],
    input: ['Input Devices', 'input-devices.webp', 'A scroll speed for every mouse.', 'input-devices'],
    color: ['Color Picker', 'color-picker.webp', 'Any pixel, copied in nine formats.', 'color-picker'],
    awake: ['Awake', 'awake.webp', 'Keeps your Mac on while you work.'],
    ruler: ['Ruler', 'ruler.webp', 'Measure anything on screen in pixels.', 'ruler'],
    text: ['Text Extractor', 'text-extractor.webp', 'Copy text right off the screen.', 'text-extractor'],
    events: ['Event Viewer', 'event-viewer.webp', 'App and system logs, easy to read.', 'event-viewer'],
    more: ['More coming soon', '', '']
  };
  // How each window sits, tried in order until one works at this tile width:
  //   a number: bleed off the right and bottom at that cut line (source px), with at least 48 px of window past the edge;
  //   "in": inside the tile at the shared density, with even side margins; "fit": as wide as the tile minus even margins;
  //   {bot: y}: centered, bleeding off the bottom only at source line y, with at least 24 px of window below the edge.
  // Cut lines go through empty space or icon buttons only. Fan: the whole width; on a phone the gap between the Balanced and Cool cards. Ruler: the copy icons
  // of the window it measures. Input Devices and Mac Tweaks: the empty space between row names and controls. RSync UI: past the
  // names, before the sizes; on a phone just past the names. Event Viewer: the gap between Source and Message, before the
  // "13 entries" line, past the Source names. Color Picker: between the pin and trash icons. Text Extractor: the copy icons.
  var CUT = { fan: ["fit", 926], ruler: [905], input: ["fit"], rsync: ["fit", 940], tweaks: ["fit"], events: [1836, 830], portman: ["fit"], color: [744, 715], text: ["in", 830] };
  // Source px per CSS px: 2 is 1:1 on a Retina screen, up to 2.8 still looks sharp for cut lines ("fit" may go higher). SHARED is the one density the
  // windows use wherever their cut lines allow. MIND allows 1 % above 1:1 so Color Picker can cut between its pin and trash icons.
  var MIND = 1.98, MAXD = 2.8, MAXCUT = 3, SHARED = 2.1036;
  var grid = document.querySelector('.bento'), tiles = [].slice.call(grid.querySelectorAll('.t'));

  // Card grain: blue noise (random noise minus its 3 x 3 blur), one 256 px tile, each speck light or dark with a small alpha.
  function grain() {
    var c = document.createElement('canvas'), g, im, px, a = new Float32Array(65536), x, y, i, j, s, v, n = function () { return Math.random() * 2 - 1; };
    c.width = c.height = 256; g = c.getContext('2d'); im = g.createImageData(256, 256); px = im.data;
    for (i = 0; i < 65536; i++) a[i] = (n() + n() + n()) / 3;
    for (y = 0; y < 256; y++) for (x = 0; x < 256; x++) {
      for (s = 0, i = -1; i <= 1; i++) for (j = -1; j <= 1; j++) s += a[((y + i) & 255) * 256 + ((x + j) & 255)];
      v = Math.max(-1, Math.min(1, (a[y * 256 + x] - s / 9) * 3.4)); i = (y * 256 + x) * 4;
      px[i] = px[i + 1] = px[i + 2] = v > 0 ? 255 : 0; px[i + 3] = Math.abs(v) * (v > 0 ? 5 : 9);
    }
    g.putImageData(im, 0, 0);
    grid.style.setProperty('--grain', 'url(' + c.toDataURL() + ')'); grid.style.setProperty('--gs', 256 / (devicePixelRatio || 1) + 'px');
  }

  // "More coming soon": a grid of empty app slots where tool icons fade in and out, one at a time.
  var ICONS = ['fan.webp', 'ruler.webp', 'portman.webp', 'color-picker.webp', 'input-devices.webp', 'mac-tweaks.webp', 'awake.webp', 'rsync.webp', 'text-extractor.webp', 'event-viewer.webp'];
  // The 10 lit slots start with the 10 icons, one each. Each time a slot starts to fade in it takes the next icon from a
  // deck of all icons, skipping any icon another slot is showing (visible for the first 62 % of the 12 s cycle).
  function slots() {
    var h = '', i, n = 0;
    for (i = 0; i < 30; i++) h += '<i>' + (i % 5 === 1 || i % 7 === 3 ? '<img class="ico" data-k="' + n + '" style="--dl:' + (i * 1.3 % 12).toFixed(1) + 's" src="' + IC + ICONS[n++] + '" alt="">' : '') + '</i>';
    return '<div class="art-slots">' + h + '</div>';
  }
  function cycleSlots(box) {
    var imgs = [].slice.call(box.querySelectorAll('img')), deck = [], SHOW = 12000 * .62;
    imgs.forEach(function (im) { im.t0 = -1e9; });
    function next(im) {
      var now = performance.now(), busy = imgs.filter(function (o) { return o !== im && now - o.t0 < SHOW; }).map(function (o) { return +o.dataset.k; });
      var all = ICONS.map(function (f, k) { return k; }), free = function (k) { return busy.indexOf(k) < 0; };
      if (!deck.length) deck = all;
      var j = deck.findIndex(free);
      // Only when every icon left in this round is on screen: reuse a free one from the round already shown.
      var k = j < 0 ? all.filter(free)[0] : deck.splice(j, 1)[0];
      im.dataset.k = k; im.src = IC + ICONS[k]; im.t0 = now;
    }
    imgs.forEach(function (im) { im.addEventListener('animationstart', function () { next(im); }); im.addEventListener('animationiteration', function () { next(im); }); });
  }


  // Try each way the window may sit (see CUT) and use the first that works at this tile width.
  function place(img, ways) {
    var v = img.parentNode.clientWidth, p = parseFloat(getComputedStyle(img.closest('.t')).paddingLeft), w = img.naturalWidth;
    var room = v - p, d = 0, left = 0;
    for (var i = 0; i < ways.length && !d; i++) {
      var o = ways[i], k;
      if (typeof o === 'number') { k = o / v; if (k >= MIND && k <= MAXCUT && (w - o) / k >= 48) d = k; }
      // Inside: at least one inset of room under the window too, so it never ends just short of the bottom edge.
      else if (o === 'in') { k = Math.max(SHARED, img.naturalHeight / (img.parentNode.clientHeight - p)); if (k <= MAXD && w / k <= room) { d = k; left = (room - w / d) / 2; } }
      // Bottom only: the bottom edge lands on a row divider.
      else if (o.bot) { k = o.bot / img.parentNode.clientHeight; if (k >= MIND && k <= MAXD && w / k <= room && (img.naturalHeight - o.bot) / k >= 24) { d = k; left = (room - w / d) / 2; } }
      else { k = Math.max(MIND, w / room); if (k <= MAXCUT) { d = k; left = (room - w / d) / 2; } }
    }
    if (!d) d = MAXD;
    img.style.width = w / d + 'px'; img.style.left = left + 'px';
    img.dataset.d = d.toFixed(2);
  }

  tiles.forEach(function (t) {
    var c = TOOLS[t.dataset.tool];
    var ic = c[1] ? '<img class="ic" src="' + IC + c[1] + '" alt="" width="64" height="64">' : '';
    var txt = '<p class="txt"><b>' + c[0] + '.</b>' + (c[2] ? ' ' + c[2] : '') + '</p>';
    var shot = c[3] ? '<span class="shot"><img src="' + CAP + c[3] + '/still@2x.webp?v=2.1.0" alt="' + c[0] + ' window"></span>' : '';
    var art = t.classList.contains('t-soon') ? '<div class="art" aria-hidden="true">' + slots() + '</div>' : '';
    t.innerHTML = art + ic + txt + shot + '<i class="hl" aria-hidden="true"></i>';
    if (art) cycleSlots(t.querySelector('.art'));
    var s = t.querySelector('.shot img'), go = function () { if (s.naturalWidth) place(s, CUT[t.dataset.tool]); };
    if (s) { s.addEventListener('load', go); go(); new ResizeObserver(go).observe(s.parentNode); }
  });

  // Cursor light: the soft spot and the hairline spot follow the pointer. Nothing moves.
  if (matchMedia('(hover: hover) and (pointer: fine)').matches) tiles.forEach(function (t) {
    t.addEventListener('pointermove', function (e) {
      var r = t.getBoundingClientRect();
      t.style.setProperty('--mx', (e.clientX - r.left) / r.width * 100 + '%'); t.style.setProperty('--my', (e.clientY - r.top) / r.height * 100 + '%');
    });
  });

  grain();
});
