# MacPowerToys site

Static site for macpowertoys.samhq.app. No build step and no dependencies.

- `public/` is the whole site: `index.html`, `site.css`, `site.js`, `404.html`, `_headers`, and `assets/`.
- Preview: `python3 site/preview.py` and open http://127.0.0.1:4831. Add `?theme=light` or `?theme=dark` to force a look.
- Deploy: `cd site/worker && npx wrangler deploy`. Cloudflare serves `public/` as static assets.
- Version: the worker (`worker/src/index.js`) writes the latest GitHub release into every `[data-version]` span and its `.dmg` asset into every `a[data-download]` link, cached for an hour. The HTML keeps the last known release (version and DMG link) as the fallback, so a release needs no site edit. The page always says "Notarized by Apple", so the site goes live only with a notarized release.

Every feature section has a stable id for links, such as `/#portman`, `/#fan`, and `/#mac-tweaks`. Keep the ids when you edit a section.

Screenshots in `assets/shots/` are offscreen renders of the real app views with sample data (no real apps, hosts, or files). They are WebP at 2x, and app windows carry their real traffic lights. Each screen sits on a wallpaper from `assets/wall/` (WebP copies of the owner's gradient wallpapers).

## Design picks

The owner picked these from real renders. Change them only with a new pick.

- Download button: a glass capsule (frosted, a blue light follows the pointer, the button leans up to 4 px toward it). Every copy keeps `data-download`.
- GitHub link in the top bar: an outlined capsule with the GitHub mark, a hairline, and a star that turns gold on hover. It shows the live star count from 25 stars up, else the word "Star".
- Footer: large type. Brand, the brew command, and two link columns over a hairline, then the giant "MacPowerToys" wordmark cut by the page bottom; its letters rise in turn and lift under the pointer.
- Live demos: two real-app recreations inline in `index.html` (no iframes, so they also render inside a claude.ai artifact). Each `.demo` host holds a `<template>` with its markup; `public/demos.js` mounts it in a shadow root with the shared `#demo-css` sheet and sizes it to the host box. Live CPU is the hero's panel. The Fan demo is the Fan page; its presets and RPM scale copy `FanCurve.swift` exactly, and its Cool segment reads "Custom" only for the owner's own curve, like `FanControlView.swift`. Every menu bar clock on the page shows the visitor's current time (`clock()` in `site.js`).
- Portman: a pinned scroll story. A large Mac screen with the real Portman shots sits on the left and runs off the left edge of the window. Big text on the right changes with the scroll, one ability per step, and the screen moves from one real Portman view to the next. On a phone the screen sits on top and the text below. Reduced motion swaps the steps without movement.
