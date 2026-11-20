# MacPowerToys site

Static site for macpowertoys.samhq.app. No build step and no dependencies.

- `public/` is the whole site: `index.html`, `site.css`, `site.js`, `404.html`, `_headers`, and `assets/`.
- Preview: `python3 site/preview.py` and open http://127.0.0.1:4831. Add `?theme=light` or `?theme=dark` to force a look.
- Deploy: `cd site/worker && npx wrangler deploy`. Cloudflare serves `public/` as static assets.
- Version: the worker (`worker/src/index.js`) writes the latest GitHub release into every `[data-version]` span and its `.dmg` asset into every `a[data-download]` link, cached for an hour. The HTML keeps the last known release (version and DMG link) as the fallback, so a release needs no site edit. When the release has the `release.json` that `make release` writes for a notarized DMG, the worker changes the `[data-notary]` line to "Notarized by Apple"; otherwise the line keeps the Open Anyway step.

Every feature section has a stable id for links, such as `/#portman`, `/#fan`, and `/#mac-tweaks`. Keep the ids when you edit a section.

Screenshots in `assets/shots/` are offscreen renders of the real app views with sample data (no real apps, hosts, or files). They are WebP at 2x, and app windows carry their real traffic lights. Each screen sits on a wallpaper from `assets/wall/` (WebP copies of the owner's gradient wallpapers).
