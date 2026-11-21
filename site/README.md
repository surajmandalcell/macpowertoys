# MacPowerToys site

Static site for macpowertoys.samhq.app. No build step and no dependencies.

- `public/` is the whole site: `index.html`, `site.css`, `site.js`, `404.html`, `_headers`, and `assets/`.
- Preview: `python3 site/preview.py` and open http://127.0.0.1:4831.- Deploy: `cd site/worker && npx wrangler deploy`. Cloudflare serves `public/` as static assets.
- Version: the worker (`worker/src/index.js`) writes the latest GitHub release into every `[data-version]` span and its `.dmg` asset into every `a[data-download]` link, cached for an hour. The HTML keeps the last known release (version and DMG link) as the fallback, so a release needs no site edit. The page always says "Notarized by Apple", so the site goes live only with a notarized release.

Every feature section has a stable id for links, such as `/#portman`, `/#fan`, and `/#mac-tweaks`. Keep the ids when you edit a section.

Screenshots in `assets/shots/` are offscreen renders of the real app views with sample data (no real apps, hosts, or files). They are WebP at 2x, and app windows carry their real traffic lights. Each screen sits on a wallpaper from `assets/wall/` (WebP copies of the owner's gradient wallpapers).

## Design picks

The owner picked these from real renders. Change them only with a new pick.

- Download button: a glass capsule (frosted, a blue light follows the pointer, the button leans up to 4 px toward it). Every copy keeps `data-download`.
- GitHub link in the top bar: an outlined capsule with the GitHub mark, a hairline, and a star that turns gold on hover. It shows the live star count from 25 stars up, else the word "Star". The worker (`worker/src/index.js`) fills the count into `[data-stars]` with an hour cache, so no visitor calls api.github.com; the static page with no worker shows "Star".
- Footer: large type. Brand, the brew command, and two link columns under a short hairline that fades out at both ends, then the giant "MacPowerToys" wordmark cut by the page bottom; its letters rise in turn and lift under the pointer.
- Live demos: two real-app recreations inline in `index.html` (no iframes, so they also render inside a claude.ai artifact). Each `.demo` host holds a `<template>` with its markup; `public/demos.js` mounts it in a shadow root with the shared `#demo-css` sheet and sizes it to the host box. Live CPU is the hero's panel. The Fan demo is the Fan page; its presets and RPM scale copy `FanCurve.swift` exactly, and its Cool segment reads "Custom" only for the owner's own curve, like `FanControlView.swift`. Every menu bar clock on the page shows the visitor's current time (`clock()` in `site.js`).
- One background: the "Fractal Maze" wallpaper (blurred orbs of near-black, deep teal, coral, orange, hot pink, and off-white behind fluted glass ribs, with fine grain), drawn live, turned upright, so its ribs run across. It stays dark, soft, and grainy so it never competes with the page. One fixed WebGL canvas (`background()` in `site.js`, half resolution) plus a CSS grain layer; without WebGL a static CSS gradient stands in. The orbs drift slowly left to right while Animation plays, move slower than the page (parallax), and at each chapter seam they move to that chapter's arrangement in `SCENES`.
- Snap story: every chapter and every story step is one full screen, and the page snaps to each (CSS scroll snap, so trackpad, wheel, keys, and touch all work). Every screen is a fixed layer that fits one screen at every width; the scroll only picks which one shows (`chapters()` in `site.js`). On a switch both screens crossfade while the main box slides from the old place to the new one (no scaling) and the story camera pans on from the old crop. Reduced motion only crossfades; Animation Off switches at once. No anchor link icons.
- Screen-grab realism: each tool screen is a crop of a 1920 x 1080 point Mac screen. The camera (`.s-cam`) holds the whole wallpaper and the right end of the menu bar (status icons, app icons, clock; never the Finder menus), and pans and zooms in on the step's shot: a panel under its menu bar icon with the clock in view, or a centered window. The hero and Fan demos are the top right corner of that screen too. Tool screens alternate sides (`.flip`). On a phone the screen sits on top and the text below.
- Short chapters, not a video guide: RSync UI is one moment (the pointer pauses a copy), Mac Tweaks is one moment (the pointer sets the Dock reveal delay to 0.00, which System Settings cannot do). `data-tap="x y"` on a step moves the pointer there, presses, and shows the shot's `.fx` patches.
- Headlines say what the tool does ("Keeps your Mac quiet and cool."), with one short line under them.
- No tool count anywhere. The tool story ends with "And more on the way." over the list of tools that ship today.
- Portman: its own menu bar icon (`PortmanStatusGlyph`) and its logo (`PortmanLogo`). The pointer clicks the Portman icon and a live panel opens (`portman.js`, `window.PortmanDemo`), then five steps: four dev servers, a Next.js server takes 780 MB and turns red, Stop removes it, a host is added, and its port forwarding.
- Dark only, one style set: no Light branch anywhere (no `prefers-color-scheme` rules, no light shots). App shots and live demos always show the Dark app. `assets/shots/glyph-mask.webp` is the light panel render kept only as the mask the demo's glyph recolor filters read.
- The page must survive the claude.ai artifact host, which puts `body{background:#fff;color:#000;font:14px ...}` and `color-scheme:light` above it. `site.css` forces the body transparent, its color and font, and `color-scheme:dark`; the canvas sits at z-index 0 under `main` and the footer at z-index 1. Test with that host style block on top of `index.html`, in Light and Dark, at 390 and 1440: both must look the same.
- Every artifact publish sends `site.css`, `site.js`, `demos.js`, `portman.js`, and `assets/portman/*` in `files` with `index.html`. Then check the artifact's file list against every `assets/` path the page uses. A publish of `index.html` alone once shipped the page with no styles.
- The Open arrow in the panel header has the gear's brightness in Dark (`--ptkA` in `#demo-css`).
- Animation control: Play, Pause, Off in the dock, remembered per visitor. Off by default under reduced motion.
- Tool card: open. Each chapter names its tool in a `.card` with the real icon. The dock switches six looks live: 1 Glass (recommended: a frosted chip), 2 Store (App Store row with one line), 3 Dock (a tile with the name under it), 4 Spotlight (a selected result row), 5 Pill (a menu bar item), 6 Finder (a selected icon with a blue label). `?card=store` opens one. Once the owner picks, keep it and drop the others and the card buttons.

## Add a tool

1. Copy one `<section class="ch" ...>` tool chapter in `public/index.html` and give it a stable id. Its kick holds a `.card` with the tool's icon (`assets/icons/`), name, and one line. `SCENES` in `site.js` gives each chapter a background arrangement and repeats from the start when there are more chapters.
2. In `.s-cam`, list its real shots: `class="shot pan" data-ico="mpt"` for a menu panel under an icon in the `#mbar` menu bar, or `class="shot win"` for a window. Keep the image `width` and `height` in points (or `data-w`/`data-h` on a shot with no image); script uses them to place the shot and crop the camera.
3. Write one `.st` per step: `data-shot` (the shot's index), an optional `data-spot="x y w h"` in shot points, `data-click` to click the icon first, or `data-tap="x y"` to press a point in the shot. One step means no pinning; the progress bars are made by script.
4. Add the tool's row to the list in `#tools`.
