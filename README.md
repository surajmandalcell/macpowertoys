<p align="center">
  <img src="docs/appicon.svg" width="112" height="112" alt="MacPowerToys icon">
</p>

<h1 align="center">MacPowerToys</h1>

<p align="center">
  <strong>Small macOS utilities. One native home.</strong><br>
  Measure, capture, stay awake, search history, and move files<br>
  without a pile of unrelated menu bar apps.
</p>

<p align="center">
  <a href="https://github.com/surajmandalcell/macpowertoys/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/surajmandalcell/macpowertoys?style=flat-square&color=087EFF"></a>
  <img alt="macOS 26.2 or newer" src="https://img.shields.io/badge/macOS-26.2%2B-171717?style=flat-square&logo=apple">
  <img alt="Built with Swift" src="https://img.shields.io/badge/Swift-5-F05138?style=flat-square&logo=swift&logoColor=white">
  <a href="LICENSE"><img alt="MIT license" src="https://img.shields.io/badge/license-MIT-34C759?style=flat-square"></a>
</p>

<p align="center">
  <a href="https://github.com/surajmandalcell/macpowertoys/releases/latest"><b>Download for macOS</b></a>
  &nbsp;&nbsp;·&nbsp;&nbsp;
  <a href="#build-from-source">Build from source</a>
</p>

<p align="center">
  <img src="docs/screenshots/macpowertoys-launcher.png" width="1200" alt="MacPowerToys utility launcher on a dark desktop">
</p>

<table>
  <tr>
    <td width="33%" align="center"><b>Native</b><br><sub>SwiftUI, AppKit, system materials, and proper Mac windows.</sub></td>
    <td width="33%" align="center"><b>Private</b><br><sub>Recognition, history, settings, and diagnostics stay local.</sub></td>
    <td width="33%" align="center"><b>Consistent</b><br><sub>One launcher, remembered windows, and keyboard-first controls.</sub></td>
  </tr>
</table>

## Seven focused tools

| | Tool | What it does |
|:--:|---|---|
| <img src="powertoys/Assets.xcassets/RulerLogo.imageset/icon.svg" width="30" alt=""> | **Ruler** | Measure the screen with movable, resizable rulers in pixels, millimeters, or inches. |
| <img src="powertoys/Assets.xcassets/AwakeLogo.imageset/icon.svg" width="30" alt=""> | **Awake** | Keep the Mac or display awake by duration, end time, or running process. |
| <img src="powertoys/Assets.xcassets/ColorPickerLogo.imageset/icon.svg" width="30" alt=""> | **Color Picker** | Sample the screen, copy developer formats, and search local color history. |
| <img src="powertoys/Assets.xcassets/TextExtractorLogo.imageset/icon.svg" width="30" alt=""> | **Text Extractor** | Select any screen region and copy text with on-device Apple Vision. |
| <img src="powertoys/Assets.xcassets/CloudSyncLogo.imageset/icon.svg" width="30" alt=""> | **Cloud Sync** | Plan and run copy, move, mirror, and two-way rclone transfers. |
| <img src="powertoys/Assets.xcassets/ClaudeHistoryLogo.imageset/icon.svg" width="30" alt=""> | **AI History** | Search, bookmark, and export local Claude Code conversations. |
| <img src="powertoys/Assets.xcassets/LogsLogo.imageset/icon.svg" width="30" alt=""> | **Logs** | Search and filter MacPowerToys diagnostics. |

## Designed for the Mac

<p align="center">
  <img src="docs/screenshots/cloud-sync.png" width="1200" alt="Cloud Sync completed transfer workspace on a dark desktop"><br>
  <sub><b>Cloud Sync</b> · planned rclone transfers, persistent progress, and clear completion state</sub>
</p>

<table>
  <tr>
    <td width="50%" valign="top">
      <img src="docs/screenshots/ruler.png" width="100%" alt="Ruler controls on a dark desktop"><br>
      <sub><b>Ruler</b> · multiple rulers, precise units, grouping, and per-ruler settings</sub>
    </td>
    <td width="50%" valign="top">
      <img src="docs/screenshots/awake.png" width="100%" alt="Awake controls on a dark desktop"><br>
      <sub><b>Awake</b> · precise display, time, and process controls</sub>
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <img src="docs/screenshots/color-picker.png" width="100%" alt="Color Picker history on a dark desktop"><br>
      <sub><b>Color Picker</b> · compact, searchable color history</sub>
    </td>
    <td width="50%" valign="top">
      <img src="docs/screenshots/text-extractor.png" width="100%" alt="Text Extractor controls on a dark desktop"><br>
      <sub><b>Text Extractor</b> · fast, private text recognition</sub>
    </td>
  </tr>
</table>

## Build from source

You need macOS 26.2+, Xcode 26.2+, and
[rclone](https://rclone.org/install/) for Cloud Sync.

```bash
brew install rclone
git clone https://github.com/surajmandalcell/macpowertoys.git
cd macpowertoys
make build
```

Open `powertoys.xcodeproj` and run the `powertoys` scheme, or
use `make build ADHOC=1` on a Mac without an Apple Development
identity. Raycast users can import the `raycast` directory;
the extension exposes only the main app and its seven tools.

> [!NOTE]
> Personal-team signing works on the signing Mac. Public,
> warning-free distribution requires Developer ID signing and
> Apple notarization.

## Cloud Sync is powered by rclone

MacPowerToys gives the excellent open-source
[rclone](https://rclone.org/) project a native Mac interface.
Provider credentials and remote configuration remain under
rclone's control.

Every transfer is dry-run planned before data moves. Completed
progress survives relaunches, **Recalculate** only adds newly
discovered work, and each transfer keeps its latest 100 local
changes. Never replace a running installation during a transfer.

## Privacy and security

- Text recognition runs locally with Apple Vision.
- Histories, logs, settings, and window positions stay local.
- Cloud credentials remain in rclone's local configuration.
- The rclone control API uses a fresh random credential per launch.
- Marketplace apps require a declared checksum, Developer ID,
  bundle identity, and Apple notarization.

Read the [Privacy Policy](PRIVACY.md),
[Security Policy](SECURITY.md), and
[Contributing Guide](CONTRIBUTING.md).

<p align="center">
  Made for macOS · Released under the <a href="LICENSE">MIT License</a>
</p>
