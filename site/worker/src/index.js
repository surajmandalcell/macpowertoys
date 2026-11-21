// Serves the static site and writes the latest GitHub release into the page: the version into every
// [data-version] span, the release's DMG into every [data-download] link, and "Notarized by Apple" into
// [data-notary] when the release says so.
// The HTML keeps the last known release, so a GitHub outage or a missing release changes nothing.
const REPO = 'surajmandalcell/macpowertoys';
const TTL = 3600;

async function latestRelease(ctx) {
  const cache = caches.default;
  const key = new Request(`https://cache.internal/${REPO}/latest-release`);
  const hit = await cache.match(key);
  if (hit) return hit.json();
  let release = {};
  try {
    const res = await fetch(`https://api.github.com/repos/${REPO}/releases/latest`, {
      headers: { 'User-Agent': 'macpowertoys-site', Accept: 'application/vnd.github+json' },
    });
    if (res.ok) {
      const body = await res.json();
      const tag = String(body.tag_name || '');
      if (/^v?\d+\.\d+\.\d+$/.test(tag)) release.version = tag.replace(/^v/, '');
      const dmg = (body.assets || []).find((a) => /\.dmg$/i.test(a.name || ''));
      if (dmg && /^https:\/\/github\.com\//.test(dmg.browser_download_url)) release.dmg = dmg.browser_download_url;
      // `make release` writes release.json only for a notarized DMG; without it the page keeps the quarantine step
      // (a Development-signed app opens as "damaged", with no Open Anyway button).
      const note = (body.assets || []).find((a) => a.name === 'release.json');
      if (note && release.version && /^https:\/\/github\.com\//.test(note.browser_download_url)) {
        const info = await (await fetch(note.browser_download_url, { headers: { 'User-Agent': 'macpowertoys-site' } })).json();
        release.notarized = info.notarized === true && info.version === release.version;
      }
    }
  } catch {}
  // An empty entry is cached too, so a missing release costs one GitHub call an hour, not one per visit.
  ctx.waitUntil(cache.put(key, new Response(JSON.stringify(release), { headers: { 'Cache-Control': `max-age=${TTL}` } })));
  return release;
}

export default {
  async fetch(request, env, ctx) {
    const res = await env.ASSETS.fetch(request);
    if (!(res.headers.get('Content-Type') || '').includes('text/html')) return res;
    const { version, dmg, notarized } = await latestRelease(ctx);
    if (!version && !dmg) return res;
    const page = new HTMLRewriter();
    if (version) page.on('[data-version]', { element(el) { el.setInnerContent(version); } });
    if (dmg) page.on('a[data-download]', { element(el) { el.setAttribute('href', dmg); } });
    if (notarized) page.on('[data-notary]', { element(el) { el.setInnerContent('Notarized by Apple'); } });
    return page.transform(res);
  },
};
