// Serves the static site and writes live GitHub facts into the page: the latest release version into every
// [data-version] span, the release's DMG into every [data-download] link, and the star count into [data-stars].
// The HTML keeps the last known release and the word "Star", so a GitHub outage changes nothing.
// Visitors never call api.github.com; the worker does, at most twice an hour.
const REPO = 'surajmandalcell/macpowertoys';
const TTL = 3600;
const MIN_STARS = 25;
const GH = { headers: { 'User-Agent': 'macpowertoys-site', Accept: 'application/vnd.github+json' } };

async function ghJSON(path) {
  try {
    const res = await fetch(`https://api.github.com/repos/${REPO}${path}`, GH);
    return res.ok ? await res.json() : null;
  } catch {
    return null;
  }
}

function starLabel(c) {
  if (!(c >= MIN_STARS)) return null;
  return c >= 1000 ? (c / 1000).toFixed(c < 10000 ? 1 : 0).replace(/\.0$/, '') + 'k' : String(c);
}

async function githubFacts(ctx) {
  const cache = caches.default;
  const key = new Request(`https://cache.internal/${REPO}/site-facts`);
  const hit = await cache.match(key);
  if (hit) return hit.json();
  const facts = {};
  const [release, repo] = await Promise.all([ghJSON('/releases/latest'), ghJSON('')]);
  if (release) {
    const tag = String(release.tag_name || '');
    if (/^v?\d+\.\d+\.\d+$/.test(tag)) facts.version = tag.replace(/^v/, '');
    const dmg = (release.assets || []).find((a) => /\.dmg$/i.test(a.name || ''));
    if (dmg && /^https:\/\/github\.com\//.test(dmg.browser_download_url)) facts.dmg = dmg.browser_download_url;
  }
  const stars = starLabel(repo && repo.stargazers_count);
  if (stars) facts.stars = stars;
  // An empty entry is cached too, so a GitHub outage costs two calls an hour, not two per visit.
  ctx.waitUntil(cache.put(key, new Response(JSON.stringify(facts), { headers: { 'Cache-Control': `max-age=${TTL}` } })));
  return facts;
}

export default {
  async fetch(request, env, ctx) {
    const res = await env.ASSETS.fetch(request);
    if (!(res.headers.get('Content-Type') || '').includes('text/html')) return res;
    const { version, dmg, stars } = await githubFacts(ctx);
    if (!version && !dmg && !stars) return res;
    const page = new HTMLRewriter();
    if (version) page.on('[data-version]', { element(el) { el.setInnerContent(version); } });
    if (dmg) page.on('a[data-download]', { element(el) { el.setAttribute('href', dmg); } });
    if (stars) page.on('[data-stars]', { element(el) { el.setInnerContent(stars); } });
    return page.transform(res);
  },
};
