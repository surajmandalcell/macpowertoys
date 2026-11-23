# MacPowerToys site

Static site for macpowertoys.samhq.app. No build step and no dependencies.

- `public/` is the whole site: `index.html`, `site.css` (page, hero, footer), `mid.css` (tool tiles), `site.js` (grain, scroll bar, copy, clock), `bento.js` (tool tiles), `demos.js` with `demo.css` and `panel.html` (the hero's live panel), `404.html`, `_headers`, and `assets/`.
- Preview: `python3 site/preview.py` and open http://127.0.0.1:4831.
- Deploy: `cd site/worker && npx wrangler deploy`. Cloudflare serves `public/` as static assets.
- Version: the worker (`worker/src/index.js`) writes the latest GitHub release into every `[data-version]` span and its `.dmg` asset into every `a[data-download]` link, cached for an hour. It also fills the star count into `[data-stars]`, so no visitor calls api.github.com. The HTML keeps the last known release as the fallback, so a release needs no site edit. The site goes live only with a notarized release; the page does not mention notarization.

Every tool tile has a stable id for links, such as `/#portman`, `/#fan`, and `/#mac-tweaks`. Keep the ids when you edit a tile.

## Design picks

The owner picked these from real renders. Change them only with a new pick.

- Dark only, one style set: no Light branch anywhere. App captures always show the Dark app. `site.css` forces the body transparent, its color and font, and `color-scheme:dark`, so the page also survives the claude.ai artifact host style block.
- Page: hero, one tool section, footer. No scroll snap, no tool count anywhere.
- Hero: headline, one short line, the Download button, the brew command, and the version line. On the right, the live menu panel (`demos.js` mounts `panel.html` with `demo.css` in a shadow root) on the ring wallpaper.
- Background: the blurred "Fractal Maze" wallpaper (`assets/wall/maze-blur-4k.webp`) with per-pixel film grain drawn by WebGL (`grain()` in `site.js`).
- Tool section: heading "Everything your Mac is missing.", then a bento of static tiles. Six columns: Fan 4 + Ruler 2; Portman 2 + Input Devices 2 + Color Picker 2; Mac Tweaks 4 + Text Extractor 2; RSync UI 6; Awake as a short full-width strip (icon and line side by side); Event Viewer 4 + More coming soon 2. On a phone every tile stacks in that order.
- Tile: icon, the tool name in white and one line in gray, then a real capture of the window. Captures are `assets/captures/<tool>/still@2x.webp` (WebP q90, density 2). `CUT` in `bento.js` sets where each window is cut by the tile edge; cuts land in empty space, never on text, a time, or a number.
- Card tone "Darker still": a solid fill (`#1e1e21` to `#151517`) with a blue-noise grain tile made by `grain()` in `bento.js`, an inset hairline on all four sides, and a soft dark shadow. Hover shows only a soft tinted light under the pointer; nothing moves.
- More coming soon: "Slots", a grid of empty app slots where the tool icons fade in and out, never two of the same icon at once, cycling through all of them. Reduced motion shows a few icons still.
- Tool icons are `assets/tools/<tool>.webp` (128 px, WebP q92, made from the 512 px app icon).
- Text: one short line per text blob, plain words. Headlines say what a tool does.
- Footer: brand, the brew command, and two link columns, then the giant "MacPowerToys" wordmark cut by the page bottom.
- Scroll bar: a thin custom knob over a hidden native bar, shown while scrolling or on hover.

## Add a tool

1. Add a `.t` tile in the `.bento` of `public/index.html` with a stable `id`, a `data-tool` key, and a `grid-area`; add the area to the grid in `mid.css` (desktop and phone).
2. Add the tool to `TOOLS` in `bento.js` (name, icon, line, capture folder), its `CUT`, and its icon to `ICONS` for the Slots card.
3. Put the capture at `assets/captures/<folder>/still@2x.webp` and the icon at `assets/tools/<tool>.webp`.
