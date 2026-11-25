<p align="center">
  <img src="docs/readme/icon.png" alt="MacPowerToys app icon" width="112" height="112">
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/readme/wordmark-dark.png">
    <img src="docs/readme/wordmark-light.png" alt="MacPowerToys" height="44">
  </picture>
</p>

<p align="center">
  <b>Ten handy Mac tools in one menu bar app.</b><br>
  Free and open source.
</p>

<p align="center">
  <a href="https://github.com/samhqapp/macpowertoys/releases/latest"><b>Download for Mac</b></a> &nbsp;·&nbsp;
  <a href="https://macpowertoys.samhq.app/">Website</a> &nbsp;·&nbsp;
  <a href="#installation">Installation</a> &nbsp;·&nbsp;
  <a href="https://github.com/samhqapp/macpowertoys/issues">Report a problem</a>
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/readme/bento-dark.webp">
    <img src="docs/readme/bento-light.webp" alt="Four tools: RSync UI copies files to Google Drive, S3 and other clouds. The menu panel shows CPU, memory, network and fan speed. Portman shows every open port and lets you stop it. Mac Tweaks changes hidden Mac settings without Terminal." width="880">
  </picture>
</p>

## Why MacPowerToys

MacPowerToys gives you small tools that macOS does not have, all in one menu bar app.

- **One place.** See CPU, memory, network, battery and fan speed in one menu bar panel.
- **Fast.** A tool uses no CPU or memory until you open it.
- **Your choice.** Turn each tool on or off. Show it in the main panel, as its own menu bar icon, or hide it.
- **Private.** No ads and no tracking. Reading text from the screen happens on your Mac.
- **Made for Mac.** A small native app, signed and checked by Apple.

## Tools

| | Tool | What it does |
|:--:|---|---|
| <img src="site/public/assets/tools/fan.webp" width="28" alt=""> | **Fan** | Pick Quiet, Balanced, or Cool, draw your own curve, or run the fans at full speed. |
| <img src="site/public/assets/tools/ruler.webp" width="28" alt=""> | **Ruler** | Measure anything on screen in pixels, millimeters, or inches. |
| <img src="site/public/assets/tools/awake.webp" width="28" alt=""> | **Awake** | Keep the Mac awake for a time, until a time, or while an app runs. |
| <img src="site/public/assets/tools/color-picker.webp" width="28" alt=""> | **Color Picker** | Pick any pixel, copy it in nine formats, and keep colors in projects. |
| <img src="site/public/assets/tools/text-extractor.webp" width="28" alt=""> | **Text Extractor** | Select part of the screen and copy its text. |
| <img src="site/public/assets/tools/portman.webp" width="28" alt=""> | **Portman** | See every port open on your Mac, which app or project started it, and stop it. Also forwards ports from an SSH server. |
| <img src="site/public/assets/tools/rsync.webp" width="28" alt=""> | **RSync UI** | Copy files to Google Drive, S3 and other clouds with rclone. Big copies can pause and continue later. |
| <img src="site/public/assets/tools/input-devices.webp" width="28" alt=""> | **Input Devices** | Set scroll direction, speed, and smoothing for mouse and trackpad. |
| <img src="site/public/assets/tools/mac-tweaks.webp" width="28" alt=""> | **Mac Tweaks** | Change hidden Dock, Finder and window settings without Terminal. Undo any time. |
| <img src="site/public/assets/tools/event-viewer.webp" width="28" alt=""> | **Event Viewer** | Read app activity and recent macOS errors. |

## Installation

<details open>
<summary><b>Mac</b> (macOS 26.2 or later)</summary>

<br>

Run this in Terminal:

```sh
brew install --cask samhqapp/tap/macpowertoys
```

Or [download the `.dmg`](https://github.com/samhqapp/macpowertoys/releases/latest), open it, and drag **MacPowerToys** to **Applications**.

Then:

1. Open MacPowerToys. Its icon shows in the menu bar.
2. Turn on the tools you want.
3. Allow access only when a tool asks. Each tool shows a button that opens the right privacy pane.

</details>

<details>
<summary>Permissions and extra parts</summary>

<br>

| Tool | What it needs |
| --- | --- |
| Text Extractor | Screen Recording |
| Input Devices, the Pick Color shortcut | Accessibility |
| Fan control | A signed helper. macOS asks for your password once to install it. |
| RSync UI | [rclone](https://rclone.org/install/): `brew install rclone` |

</details>

## Screenshots

The menu panel, Portman, Fan, RSync UI, Color Picker, Text Extractor, Mac Tweaks, Input Devices, Event Viewer, and Ruler. Click one to see it full size.

<sub>Every shot uses made-up sample data.</sub>

<p>
<a href="docs/readme/shots/menu-panel.webp"><img src="docs/readme/shots/menu-panel.webp" alt="Menu panel" width="120"></a>
<a href="docs/readme/shots/portman.webp"><img src="docs/readme/shots/portman.webp" alt="Portman server details" width="120"></a>
<a href="docs/readme/shots/fan.webp"><img src="docs/readme/shots/fan.webp" alt="Fan" width="120"></a>
<a href="docs/readme/shots/rsync.webp"><img src="docs/readme/shots/rsync.webp" alt="RSync UI" width="120"></a>
<a href="docs/readme/shots/color-picker.webp"><img src="docs/readme/shots/color-picker.webp" alt="Color Picker" width="120"></a>
<a href="docs/readme/shots/text-extractor.webp"><img src="docs/readme/shots/text-extractor.webp" alt="Text Extractor" width="120"></a>
<a href="docs/readme/shots/mac-tweaks.webp"><img src="docs/readme/shots/mac-tweaks.webp" alt="Mac Tweaks" width="120"></a>
<a href="docs/readme/shots/input-devices.webp"><img src="docs/readme/shots/input-devices.webp" alt="Input Devices" width="120"></a>
<a href="docs/readme/shots/event-viewer.webp"><img src="docs/readme/shots/event-viewer.webp" alt="Event Viewer" width="120"></a>
<a href="docs/readme/shots/ruler.webp"><img src="docs/readme/shots/ruler.webp" alt="Ruler" width="120"></a>
</p>

## Learn more

<details>
<summary><b>Keyboard shortcuts</b></summary>

<br>

| Shortcut | Action |
| --- | --- |
| Command-Shift-3 | Pick a color, in any app |
| Command-Shift-2 | Copy text from part of the screen, in any app |
| Option-Command-P | Open Portman, in any app |
| Command-1 to Command-9 | Open launcher pages: All tools, then the first eight tools |
| Command-O | Open the selected tool |
| Command-F | Search in the current window |
| Command-comma | Open settings for the current window |
| Command-W | Close the window. The app keeps running in the menu bar. |
| Option-Command-Q | Quit MacPowerToys |

Change or turn off the global shortcuts in each tool's settings.

</details>

<details>
<summary><b>Privacy</b></summary>

<br>

MacPowerToys has no accounts, no ads, and no tracking. Text recognition runs on your Mac. Anonymous daily counts (app version, macOS version, and chip) are sent once a day. They are on by default; turn off "Share anonymous usage" in Settings to stop them. rclone keeps your cloud logins in its own settings file. Optional iCloud settings sync never syncs logins, paths, histories, or logs.

[Privacy Policy](https://macpowertoys.samhq.app/privacy) · [Terms and license](https://macpowertoys.samhq.app/terms) · [Security Policy](SECURITY.md)

</details>

<details>
<summary><b>Limits</b></summary>

<br>

- RSync UI cannot reorder files inside a running folder transfer. A paused file can restart; finished files stay complete.
- Google Drive setup needs your own OAuth client ID.
- Input Devices tells mouse and trackpad apart by event type. macOS does not say which device sent each scroll.
- macOS restores a window's position and display, but not its Space.

</details>

<details>
<summary><b>Build it yourself</b></summary>

<br>

```sh
brew install rclone
git clone https://github.com/samhqapp/macpowertoys.git
cd macpowertoys
make build          # or: make build ADHOC=1 without an Apple Development identity
```

[Development guide](docs/DEVELOPMENT.md) · [Contributing](CONTRIBUTING.md) · [Changelog](CHANGELOG.md) · [Build your own tool](docs/MARKETPLACE_TOOLS.md)

Partition Manager, System Cleaner, Task Manager, and Sam's Network Utilities are separate apps now. Every window uses [OnePlusUI](https://github.com/samhqapp/oneplus-ui), a SwiftUI component package.

</details>

<details>
<summary><b>Credits</b></summary>

<br>

Ruler includes [Free Ruler](https://github.com/pascalpp/FreeRuler) by Pascal Balthrop (MIT, [license](powertoys/FreeRuler/FreeRuler-LICENSE.txt)). The fan reader adapts code from [smctl](https://github.com/leaperone/smctl) (MIT, [license](powertoys/Core/smctl-LICENSE.txt)). RSync UI is a native app for [rclone](https://rclone.org/). The menu bar glyph is adapted from [Lucide](https://lucide.dev) (ISC).

</details>

<br>

<p align="center">
  If you like MacPowerToys, please give it a star on GitHub. It helps more people find it.<br>
  <a href="https://github.com/samhqapp/macpowertoys"><b>⭐ Star MacPowerToys on GitHub</b></a>
</p>

## License

MacPowerToys is released under the [MIT license](LICENSE).
