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
- One story: the page is a row of chapters (`section.ch`), each on its own dark moving background in the tool's colors, with the same space at every seam. Every tool is a pinned scroll story: a large Mac screen on the left runs off the window edge, big text on the right changes with the scroll, one feature per step, and a spotlight dims all but the part the step is about. On a phone the screen sits on top and the text below. Reduced motion swaps steps without movement.
- No tool count anywhere. The tool story ends with "And more on the way." over the list of tools that ship today.
- Portman: its own menu bar icon (`PortmanStatusGlyph`) and its logo (`PortmanLogo`). The pointer clicks the Portman icon and the panel opens, then seven steps: the icon, the summary ring, the server rows, live graphs, Restart, SSH forwarding, and the settings window.
- Page chrome is always dark. App shots and live demos still follow the visitor's Light or Dark setting.
- The Open arrow in the panel header has the gear's brightness in Dark (`--ptkA` in `#demo-css`).
- Animation control: Play, Pause, Off in the dock, remembered per visitor. Off by default under reduced motion. Only chapters on screen animate.
- Background style: open. The dock switches four styles live: 1 Wall (recommended: a darkened real wallpaper from `assets/bg/` that drifts, with a glow in the tool's color), 2 Mesh (three orbiting color blobs), 3 Aurora (sweeping bands), 4 Grain (a two-tone gradient under heavy film grain). `?bg=mesh` opens a style. Once the owner picks, keep that style and drop the other three and the style buttons; the Animation control stays.

## Add a tool

1. Copy one `<section class="ch" ...>` tool chapter in `public/index.html` and give it a stable id, a `data-bg-wall` (a file in `assets/bg/`), and three colors `--c1`, `--c2`, `--c3`.
2. In `.s-cam`, list its real shots: `class="shot pan" data-ico="mpt"` for a menu panel under an icon in the `#mbar` menu bar, or `class="shot win"` for a window. Keep the image `width` and `height` in points; script uses them for the zoom.
3. Write one `.st` per step: `data-shot` (the shot's index), an optional `data-spot="x y w h"` in shot points, and `data-click` to click the icon first. One step means no pinning; the progress bars are made by script.
4. Add the tool's row to the list in `#tools`.
