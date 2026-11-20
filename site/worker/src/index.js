// Serves the static site and writes the latest GitHub release version into every [data-version] span.
// The HTML keeps the last known version, so a GitHub outage or a missing release changes nothing.
const REPO = 'surajmandalcell/macpowertoys';
const TTL = 3600;

async function latestVersion(ctx) {
  const cache = caches.default;
  const key = new Request(`https://cache.internal/${REPO}/latest-version`);
  const hit = await cache.match(key);
  if (hit) return (await hit.text()) || null;
  let version = '';
  try {
    const res = await fetch(`https://api.github.com/repos/${REPO}/releases/latest`, {
      headers: { 'User-Agent': 'macpowertoys-site', Accept: 'application/vnd.github+json' },
    });
    if (res.ok) {
      const tag = String((await res.json()).tag_name || '');
      if (/^v?\d+\.\d+\.\d+$/.test(tag)) version = tag.replace(/^v/, '');
    }
  } catch {}
  // An empty entry is cached too, so a missing release costs one GitHub call an hour, not one per visit.
  ctx.waitUntil(cache.put(key, new Response(version, { headers: { 'Cache-Control': `max-age=${TTL}` } })));
  return version || null;
}

export default {
  async fetch(request, env, ctx) {
    const res = await env.ASSETS.fetch(request);
    if (!(res.headers.get('Content-Type') || '').includes('text/html')) return res;
    const version = await latestVersion(ctx);
    if (!version) return res;
    return new HTMLRewriter().on('[data-version]', { element(el) { el.setInnerContent(version); } }).transform(res);
  },
};
