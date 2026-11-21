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
- One background: the "Fractal Maze" wallpaper (blurred orbs of near-black, deep teal, coral, orange, hot pink, and off-white behind fluted glass ribs, with fine grain), drawn live, turned upright, so its ribs run across. One fixed WebGL canvas (`background()` in `site.js`, half resolution) plus a CSS grain layer; without WebGL a static CSS gradient stands in. The orbs drift slower than the page, and at each chapter seam they move to that chapter's arrangement in `SCENES`.
- Snap story: every chapter and every story step is one full screen, and the page snaps to each (CSS scroll snap, so trackpad, wheel, keys, and touch all work). Every screen is a fixed layer that fits one screen at every width; the scroll only picks which one shows (`chapters()` in `site.js`). On a switch both screens crossfade while the old main box flies into the new one's place and the new one grows out of its anchor: the panel's Fan row into the Fan page, the Portman icon into its screen, the MacPowerToys icon into RSync UI and Input Devices (`data-from` on the chapter), else the old main box. Web Animations with transform and opacity only, so every browser morphs; reduced motion only crossfades, and Animation Off switches at once. Inside a chapter, steps slide the spotlight and swap shots in place. Each tool screen sits on the left and runs off the window edge, big text on the right, and a spotlight dims all but the part the step is about. On a phone the screen sits on top and the text below.
- Headlines say what the tool does ("Keeps your Mac quiet and cool."), with one short line under them.
- No tool count anywhere. The tool story ends with "And more on the way." over the list of tools that ship today.
- Portman: its own menu bar icon (`PortmanStatusGlyph`) and its logo (`PortmanLogo`). The pointer clicks the Portman icon and the panel opens, then seven steps: the icon, the summary ring, the server rows, live graphs, Restart, SSH forwarding, and the settings window.
- Page chrome is always dark. App shots and live demos still follow the visitor's Light or Dark setting.
- The Open arrow in the panel header has the gear's brightness in Dark (`--ptkA` in `#demo-css`).
- Animation control: Play, Pause, Off in the dock, remembered per visitor. Off by default under reduced motion.
- Tool card: open. Each chapter names its tool in a `.card` with the real icon. The dock switches six looks live: 1 Glass (recommended: a frosted chip), 2 Store (App Store row with one line), 3 Dock (a tile with the name under it), 4 Spotlight (a selected result row), 5 Pill (a menu bar item), 6 Finder (a selected icon with a blue label). `?card=store` opens one. Once the owner picks, keep it and drop the others and the card buttons.

## Add a tool

1. Copy one `<section class="ch" ...>` tool chapter in `public/index.html` and give it a stable id. Its kick holds a `.card` with the tool's icon (`assets/icons/`), name, and one line. `SCENES` in `site.js` gives each chapter a background arrangement and repeats from the start when there are more chapters.
2. In `.s-cam`, list its real shots: `class="shot pan" data-ico="mpt"` for a menu panel under an icon in the `#mbar` menu bar, or `class="shot win"` for a window. Keep the image `width` and `height` in points; script uses them for the zoom.
3. Write one `.st` per step: `data-shot` (the shot's index), an optional `data-spot="x y w h"` in shot points, and `data-click` to click the icon first. One step means no pinning; the progress bars are made by script.
4. Add the tool's row to the list in `#tools`.
