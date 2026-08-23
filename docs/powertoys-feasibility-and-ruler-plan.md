# macOS PowerToys feasibility and ruler direction

> [!IMPORTANT]
> The Ruler implementation section is superseded by the pinned FreeRuler parity
> plan in `docs/superpowers/plans/2026-08-01-freeruler-parity.md`. The current
> product intentionally removes the earlier custom SwiftUI ruler, guides,
> calibration, measurement capture, and developer copy features.

Research date: 2026-07-13

## Executive answer

The best first applet is a **manual floating ruler**, not a pixel-edge detector. A
Free Ruler-class implementation is small, useful, compatible with the Mac App
Store sandbox, and needs no privacy permission. The PowerToys-style automatic
Screen Ruler can follow later because it needs screen capture consent and image
edge-detection work.

The estimates below mean one experienced macOS engineer working inside the
existing SwiftUI/AppKit app. They include a usable UI and basic tests, but not a
large extension ecosystem or months of compatibility hardening.

## Feasibility table, easiest to hardest

| # | Utility and Windows purpose | macOS equivalent / competition | Likely macOS implementation | Permission, sandbox, and API reality | Estimate / verdict |
|---:|---|---|---|---|---|
| 1 | **Awake** - temporarily prevent system or display sleep ([Microsoft](https://learn.microsoft.com/en-us/windows/powertoys/awake)) | `caffeinate`; [KeepingYouAwake](https://github.com/newmarcel/KeepingYouAwake) | IOKit power assertions (`IOPMAssertionCreateWithName`) with timer/menu state | No privacy permission. Works sandboxed if the power-management call remains allowed. | **1-2 days - Easy** |
| 2 | **Color Picker** - sample any screen color and copy formatted values ([Microsoft](https://learn.microsoft.com/en-us/windows/powertoys/color-picker)) | Apple's [Digital Color Meter](https://support.apple.com/guide/digital-color-meter/welcome/mac) | AppKit [`NSColorSampler`](https://developer.apple.com/documentation/appkit/nscolorsampler), `NSColor`, `NSPasteboard` | No broad screen capture is required when using the system sampler. Global activation shortcut is the only integration wrinkle. | **2-3 days - Easy** |
| 3 | **Image Resizer** - batch resize images from Explorer ([Microsoft](https://learn.microsoft.com/en-us/windows/powertoys/image-resizer)) | Preview; Finder Quick Actions | Image I/O / Core Graphics, preserving orientation and metadata; expose through Services or a Finder action | File access is naturally user-selected. Sandboxed and App Store-safe. Format and metadata test matrix adds work. | **3-5 days - Easy** |
| 4 | **PowerRename** - previewed bulk regex rename in Explorer ([Microsoft](https://learn.microsoft.com/en-us/windows/powertoys/powerrename)) | Finder's built-in Rename; Automator | `FileManager`, regex, collision planner, undo journal, Finder Service/action | User-selected file URLs work in sandbox. Must handle case-only renames, collisions, packages, iCloud placeholders, and rollback. | **4-7 days - Easy** |
| 5 | **Peek** - fast file preview without opening the owning app ([Microsoft](https://learn.microsoft.com/en-us/windows/powertoys/peek)) | macOS Quick Look | [`QuickLook`](https://developer.apple.com/documentation/quicklook) preview panel/session | Previewing a URL the user selected is public and sandbox-safe. Exact "current Finder selection + global shortcut" needs Finder integration or Apple Events and is less clean. | **4-8 days - Easy for in-app; Moderate for exact parity** |
| 6 | **New+** - create files/folders from reusable templates in Explorer ([Microsoft](https://learn.microsoft.com/en-us/windows/powertoys/newplus)) | Finder Services / Automator Quick Actions | Template library, `FileManager`, Service/action receiving the destination folder | Sandboxed if the destination comes from a user action or security-scoped bookmark. Finder Sync is officially aimed at sync clients, so do not misuse it solely as a context-menu injector ([Apple](https://developer.apple.com/documentation/findersync)). | **5-8 days - Moderate** |
| 7 | **Advanced Paste** - clipboard transforms, OCR, transcoding, and optional AI ([Microsoft](https://learn.microsoft.com/en-us/windows/powertoys/advanced-paste)) | macOS clipboard history; [Maccy](https://github.com/p0deje/Maccy) | `NSPasteboard`, Uniform Type Identifiers, Vision OCR, Image I/O, AVFoundation; optional model/provider adapters | Basic transforms are sandbox-safe. Clipboard history needs a background observer; AI needs privacy disclosure/key storage. Full media and AI parity greatly expands scope. | **1-3 weeks - Moderate** |
| 8 | **Text Extractor** - select a screen region and copy OCR text ([Microsoft](https://learn.microsoft.com/en-us/windows/powertoys/text-extractor)) | Live Text in Apple apps; CleanShot and TextSniper commercially | [`ScreenCaptureKit`](https://developer.apple.com/documentation/screencapturekit) region capture + Vision [`RecognizeTextRequest`](https://developer.apple.com/documentation/vision/recognizetextrequest) | Requires Screen & System Audio Recording consent. Public APIs and sandbox-compatible after consent. Multi-display coordinates and first-run UX are the real work. | **1-2 weeks - Moderate** |
| 9 | **Screen Ruler** - measure screen pixels using image edge detection ([Microsoft](https://learn.microsoft.com/en-us/windows/powertoys/screen-ruler)) | [Free Ruler](https://github.com/pascalpp/FreeRuler) for manual rulers; PixelSnap commercially | Manual AppKit overlay first; exact parity adds ScreenCaptureKit, edge detection, selection overlays, and scale conversion | Manual ruler needs no permission. Automatic measurement needs Screen Recording. Retina points, backing pixels, display rotation, and mixed scaling require explicit semantics. | **3-6 days manual; 2-3 weeks exact - Moderate** |
| 10 | **File Explorer Add-ons** - preview and thumbnail handlers for developer/design formats ([Microsoft](https://learn.microsoft.com/en-us/windows/powertoys/file-explorer)) | Native Quick Look and third-party Quick Look plug-ins | `QLPreviewProvider` and `QLThumbnailProvider` extensions; parser/renderers per format ([Apple Quick Look Thumbnailing](https://developer.apple.com/documentation/quicklookthumbnailing)) | Official extension points and App Store-safe. Difficulty is proportional to formats, safe parsing, memory limits, and fidelity. | **1-2 weeks per small format set - Moderate** |
| 11 | **Command Not Found** - suggest installable packages when a shell command is missing ([Microsoft](https://learn.microsoft.com/en-us/windows/powertoys/cmd-not-found)) | [Homebrew command-not-found](https://github.com/Homebrew/homebrew-command-not-found) | Opt-in zsh/bash hook, local Homebrew formula index or `brew` query, install command copied rather than silently run | Shell initialization files sit outside a sandbox container. Installation must be explicit and reversible; Mac App Store distribution is a poor fit. | **1-2 weeks - Moderate, direct distribution preferred** |
| 12 | **Environment Variables** - manage user/system variables and profiles ([Microsoft](https://learn.microsoft.com/en-us/windows/powertoys/environment-variables)) | Shell dotfiles and `launchctl`; no single macOS equivalent | Parse and safely edit `.zshenv`, `.zprofile`, `.bash_profile`, etc.; optionally generate snippets | macOS has no single global environment-variable store. Shell, GUI-app, launch-agent, and per-process scopes differ. Sandbox cannot freely rewrite dotfiles without user-granted access. | **1-2 weeks for shell profiles - Moderate; full parity is not coherent** |
| 13 | **PowerToys Run** - plugin-based app/file/command launcher ([Microsoft](https://learn.microsoft.com/en-us/windows/powertoys/run)) | Spotlight, Alfred, [Raycast](https://developers.raycast.com/) | `NSWorkspace`, Spotlight metadata queries, calculator/unit engines, ranked providers, global hotkey | Public APIs cover a useful launcher. Shell execution, file indexing, plugin isolation, ranking, and polish make this a product rather than a small utility. | **3-6 weeks - Moderate to Hard** |
| 14 | **Quick Accent** - hold a character and select accented variants ([Microsoft](https://learn.microsoft.com/en-us/windows/powertoys/quick-accent)) | macOS's built-in press-and-hold accent menu | Global key observation, overlay, and synthetic Unicode insertion through event services or Accessibility | Needs Input Monitoring and/or Accessibility for reliable arbitrary-app behavior; secure-input fields and some apps remain unavailable. It duplicates native macOS behavior. | **2-4 weeks - Hard, low value** |
| 15 | **Mouse Utilities** - locate/highlight the pointer, crosshairs, click indicators, and jump ([Microsoft](https://learn.microsoft.com/en-us/windows/powertoys/mouse-utilities)) | macOS shake-to-locate; presentation utilities | Transparent per-screen overlays, global event monitor/event tap, cursor tracking | Passive location/highlight can be fairly clean; global clicks and injected movement require Input Monitoring or Accessibility. Spaces/full-screen behavior needs extensive QA. | **2-4 weeks - Hard** |
| 16 | **Grab And Move** - modifier-drag anywhere to move/resize another app's window ([Microsoft](https://learn.microsoft.com/en-us/windows/powertoys/grab-and-move)) | [Easy Move+Resize](https://github.com/dmarcotte/easy-move-resize); Hammerspoon | `CGEventTap` for gesture capture + `AXUIElement` position/size writes | Requires Input Monitoring and Accessibility. Some apps expose incomplete/non-settable accessibility geometry; secure input can suppress observation. | **2-4 weeks - Hard** |
| 17 | **FancyZones** - custom snapping layouts and zone-aware dragging ([Microsoft](https://learn.microsoft.com/en-us/windows/powertoys/fancyzones)) | [Rectangle](https://rectangleapp.com/), Moom, Magnet | Accessibility window enumeration/move/resize, drag overlay, layout editor, display/Space persistence | Requires Accessibility. macOS does not expose a first-class third-party window-manager API; AX works but is app-dependent and must survive monitor/Space changes. | **4-8 weeks - Hard** |
| 18 | **Shortcut Guide** - overlay shortcuts available in the current desktop/app context ([Microsoft](https://learn.microsoft.com/en-us/windows/powertoys/shortcut-guide)) | macOS menu search; KeyClu/CheatSheet-style apps | Inspect front app's menu tree through Accessibility, merge known system shortcuts, render overlay | Requires Accessibility for other apps. There is no public complete registry of contextual shortcuts; non-menu shortcuts are undiscoverable, so results will always be partial. | **3-6 weeks - Hard and inherently incomplete** |
| 19 | **Crop And Lock** - show a live cropped view or interactive thumbnail of another window ([Microsoft](https://learn.microsoft.com/en-us/windows/powertoys/crop-and-lock)) | Screen-sharing picture-in-picture workflows; no exact built-in | ScreenCaptureKit stream filtered to a window/region, floating own window, coordinate remapping for optional interaction | Capture is public but requires Screen Recording. A live mirror is feasible; forwarding arbitrary interaction into another app requires Accessibility/event injection and will be fragile. | **4-8 weeks - Hard** |
| 20 | **ZoomIt** - live presentation zoom, drawing, break timer, and recording ([Microsoft](https://learn.microsoft.com/en-us/windows/powertoys/zoomit)) | macOS Accessibility Zoom for magnification; presentation annotation apps | ScreenCaptureKit or system zoom integration, full-screen overlay/canvas, event handling, AVFoundation recording | Screen Recording for captured zoom/recording; Input Monitoring or Accessibility for global controls. Multi-display and latency-sensitive rendering make polish expensive. | **4-8 weeks - Hard** |
| 21 | **Workspaces** - save apps/windows and relaunch them into positions ([Microsoft](https://learn.microsoft.com/en-us/windows/powertoys/workspaces)) | Rectangle Pro, Moom, Hammerspoon | `NSWorkspace` launch, AX window identification and geometry restore, bookmarks/doc URLs, display topology matching | Accessibility required. Window identity is unstable across launches, apps may restore asynchronously, and Spaces are not fully controllable by public API. Best-effort only. | **5-10 weeks - Hard** |
| 22 | **Command Palette** - extensible launcher for apps, files, windows, shell, services, system actions, and plugins ([Microsoft](https://learn.microsoft.com/en-us/windows/powertoys/command-palette/overview)) | Raycast and Alfred | Everything in Run plus extension SDK/process boundary, command navigation, rich views, settings and distribution | A basic launcher uses public APIs. Competitive parity requires a secure extension platform and many integrations. Accessibility is needed for window switching; shell/file plugins strain sandbox boundaries. | **2-4 months - Hard** |
| 23 | **File Locksmith** - identify processes holding a selected file and terminate them ([Microsoft](https://learn.microsoft.com/en-us/windows/powertoys/file-locksmith)) | [Sloth](https://github.com/sveinbjornt/Sloth); `lsof` | Direct build can invoke `/usr/sbin/lsof` or use process/file-descriptor inspection, then send signals with ownership checks | A sandboxed process cannot inspect the whole machine meaningfully. Process visibility and terminating other apps are security-sensitive. Viable as a notarized direct app, not a clean Mac App Store feature. | **2-4 weeks direct - Hard / App Store-incompatible** |
| 24 | **Hosts File Editor** - safely edit and toggle entries in the system hosts file ([Microsoft](https://learn.microsoft.com/en-us/windows/powertoys/hosts-file-editor)) | [Gas Mask](https://github.com/2ndalpha/gasmask); manual `/etc/hosts` | Validating editor plus privileged helper/daemon, atomic replacement, backup and cache flush | `/etc/hosts` is root-owned. Mac App Store rule 2.4.5 forbids requesting root escalation; direct distribution needs a carefully secured privileged helper. | **2-4 weeks direct - Hard / App Store-incompatible** |
| 25 | **Mouse Without Borders** - control several computers, share clipboard, and transfer files ([Microsoft](https://learn.microsoft.com/en-us/windows/powertoys/mouse-without-borders)) | [Input Leap](https://github.com/input-leap/input-leap), Synergy, Universal Control | Authenticated encrypted peer protocol, edge switching, `CGEventPost`, clipboard/file synchronization, discovery and recovery | Accessibility/Input Monitoring required. Normal logged-in sessions are possible; lock-screen/elevated control needs privileged components and substantially increases security risk. | **2-4 months - Hard** |
| 26 | **PowerDisplay** - DDC/CI monitor brightness, contrast, input, audio, power, and profiles ([Microsoft](https://learn.microsoft.com/en-us/windows/powertoys/power-display)) | [MonitorControl](https://github.com/MonitorControl/MonitorControl), BetterDisplay | IOKit/CoreGraphics display discovery plus vendor-dependent DDC/CI transport and software fallbacks | macOS has no stable high-level public DDC/CI framework. Existing apps depend on low-level IOKit behavior and hardware-specific fallbacks; App Store viability and OS-update resilience are poor. | **2-4 months - Hard, direct distribution** |
| 27 | **Light Switch** - schedule automatic system light/dark theme changes ([Microsoft](https://learn.microsoft.com/en-us/windows/powertoys/light-switch)) | macOS Appearance already offers automatic light/dark switching | Scheduling is trivial; changing the system appearance would rely on System Events AppleScript/UI automation or undocumented preferences | Apple exposes app-local appearance but no supported API for a third-party app to set the global system appearance. Automation is permission-heavy and brittle, and App Store review is risky. | **Effectively impossible as clean exact parity; also redundant** |
| 28 | **Always On Top** - pin any other application's window above all others ([Microsoft](https://learn.microsoft.com/en-us/windows/powertoys/always-on-top)) | Float-your-own-window apps; screen-mirror workarounds | `NSWindow.Level` works only for windows the app owns. AX can raise/move other windows but cannot assign their window-server level | There is no public API to permanently change another app's window level. A captured mirror is a different product and needs Screen Recording. | **Effectively impossible without private WindowServer APIs** |
| 29 | **Keyboard Manager** - robust system-wide key and shortcut remapping ([Microsoft](https://learn.microsoft.com/en-us/windows/powertoys/keyboard-manager)) | [Karabiner-Elements](https://karabiner-elements.pqrs.org/) | Limited remapping can use event taps; robust suppression and reinjection uses a virtual HID/device or system extension architecture | Accessibility/Input Monitoring alone is incomplete around secure input and special keys. Karabiner's installation and required permissions demonstrate that production-grade remapping is a system product, not an ordinary sandboxed app. Driver/system entitlements need Apple approval. | **Effectively impossible for this App Store suite; 3-6+ months direct with approved entitlement** |
| 30 | **Registry Preview** - preview, edit, and import Windows `.reg` files ([Microsoft](https://learn.microsoft.com/en-us/windows/powertoys/registry-preview)) | No macOS Registry; Property List Editor is the nearest native concept | A `.reg` parser/viewer is possible, but importing has no macOS target. A plist preview/editor would be a different, easy utility using `PropertyListSerialization` | Exact behavior is Windows-specific and has no meaningful macOS API or data store. | **Impossible / not applicable as a port; replace with a plist tool** |

## How the ratings were derived

Apple provides excellent public building blocks for content owned by the app:
Quick Look, Vision OCR, ScreenCaptureKit, Image I/O, AppKit windows, pasteboard,
and user-selected file access. Those lead to Easy or Moderate ratings.

The difficulty jumps when a tool must observe or control other applications.
Apple's public [`AXUIElement`](https://developer.apple.com/documentation/applicationservices/axuielement_h)
API can communicate with accessible elements, but users must grant Accessibility
permission, apps can omit functionality, and it does not expose every WindowServer
capability. Screen pixels are available through ScreenCaptureKit, but only after
Screen Recording consent. Global raw input generally brings Input Monitoring or
Accessibility consent.

The Mac App Store adds a second boundary. Apple's
[App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
require public APIs and sandboxing, forbid root escalation for Mac App Store apps,
and restrict installing outside code or shared components. Therefore Hosts File
Editor, File Locksmith, deep shell integration, DDC/CI display control, and robust
keyboard remapping either need direct notarized distribution or should be omitted.

## Free Ruler evidence and first-version scope

[Free Ruler's official source](https://github.com/pascalpp/FreeRuler) is active,
MIT-licensed, sandboxed, and intentionally small. Its current feature set is:

- multiple rulers with horizontal and vertical arms;
- pixels, millimeters, and inches;
- optional floating above other apps;
- independent or grouped movement;
- show, hide, reopen, resize, and reset;
- ruler color, foreground/background opacity, optional shadow, and four zero-corner orientations;
- mouse-following tick/origin alignment and single-key shortcuts;
- multiple languages.

This is strong evidence that a Free Ruler-class applet is technically straightforward
and Mac App Store-compatible. The source uses an AppKit window/drawing model and its
App Store entitlement file contains only App Sandbox plus user-selected read access.
Its MIT license permits reuse, modification, and distribution, but the copyright and
license notice must be preserved. The PowerToys applet should still use its own name,
icon, and product design rather than presenting itself as Free Ruler.

### Recommended first cut

Ship horizontal and vertical borderless AppKit panels, drag/resize, tick labels,
pixels first, independent/grouped movement, float toggle, origin-at-pointer,
color/opacity, multi-display correctness, persistence, and keyboard shortcuts.
Add physical units only after defining calibration semantics. Add ScreenCaptureKit
edge detection as a separate second milestone so the initial applet has zero privacy
permission prompts.

## Ruler applet implementation plan

### Product decision

Build behavioral parity with Free Ruler first, then differentiate. Because Free
Ruler is MIT-licensed, selected geometry or tick-layout code may be adapted if its
copyright and license notice are retained in a third-party notices file. Do not copy
its name, icon, screenshots, or App Store presentation. A native port shaped around
PowerToys' existing architecture will be easier to maintain than dropping its Cocoa
XIB application into this SwiftUI project unchanged.

Call the tool **Ruler** internally until the wider app is renamed. Its launch promise:

> Put a precise ruler above any Mac app, without taking a screenshot or granting a
> privacy permission.

### Version 1 scope

1. Create horizontal, vertical, and joined L-shaped rulers.
2. Move a ruler by dragging its body and resize it from its far-end handle.
3. Show major, medium, and minor ticks plus a live cursor-position label.
4. Support points and backing pixels as distinct units. Never call AppKit points
   "pixels" on Retina displays.
5. Support millimeters and inches when display physical-size data is available;
   clearly label estimated values and allow per-display calibration.
6. Toggle floating level, shadow, ruler color, opacity, arm visibility, grouping,
   and any of four zero corners.
7. Set the zero point to the current pointer position and reset to a safe default.
8. Persist ruler frames and settings per display and restore only after clamping them
   to the currently connected screens.
9. Provide menu commands, context-menu commands, tooltips, and shortcuts matching
   the operations above.
10. Add an App Intent and `powertoys://open/ruler` deep link.

The version 1 ruler requires no Screen Recording, Accessibility, Input Monitoring,
or administrator permission. It should remain Mac App Store-compatible.

### Architecture in this repository

| Area | Proposed responsibility |
|---|---|
| `Models/RulerModels.swift` | Orientation, zero corner, units, calibrated display profile, ruler state, and pure geometry values |
| `Services/RulerManager.swift` | `@MainActor` owner of all ruler windows; create, close, group, ungroup, persist, and restore |
| `Views/Ruler/RulerControlView.swift` | Normal PowerToys tool window with new-ruler controls, settings, shortcut reference, and active ruler list |
| `Views/Ruler/RulerOverlayWindow.swift` | Borderless `NSPanel`/`NSWindow` subclass at normal or floating level, with Spaces/full-screen collection behavior |
| `Views/Ruler/RulerOverlayView.swift` | AppKit drawing and pointer interaction for pixel-aligned ticks, labels, body drag, and resize handle |
| `Views/Ruler/RulerSettingsView.swift` | Color, opacity, units, zero corner, shadow, float, calibration, and default lengths |
| `Models/Tool.swift` | Register `RulerTool` in the Developer category |
| `powertoysApp.swift` | Add the `ruler` control-window scene; overlay windows remain owned by `RulerManager` |
| `Core/DeepLinkHandler.swift` | Route `powertoys://open/ruler` |
| `Core/PowerToysIntents.swift` | Add Ruler to `PowerToolTarget` and expose an Open Ruler intent |
| `powertoysTests/RulerTests.swift` | Tick layout, coordinate conversion, grouping, persistence, and calibration tests |
| `powertoysUITests/RulerUITests.swift` | Launch, create ruler, resize, change units, group, close, and restore smoke tests |

Dynamic ruler overlays should not be separate SwiftUI `Window` scenes. A single
SwiftUI control window fits the current tool system, while an AppKit manager owns
the arbitrary number of borderless overlay windows needed by the ruler.

### Delivery checkpoints

| Checkpoint | Work | Acceptance criteria | Estimate |
|---|---|---|---:|
| 1. Foundation | Register tool/window/deep link; implement pure ruler geometry and tick layout | Tool opens from grid and deep link; deterministic tests cover all orientations and zero corners | 1-2 days |
| 2. Single ruler | Draw one horizontal or vertical overlay; drag body; resize far end; close/reopen | Lines remain crisp at 1x and 2x; frame never jumps on first display | 2-3 days |
| 3. Joined rulers | Horizontal, vertical, and joined modes; group/ungroup; four zero corners | Joining preserves the visible origin; arms can hide independently | 2-3 days |
| 4. Units and displays | Points/backing pixels, physical units, calibration, rotated and mixed-scale displays | Correct results on 1x/2x displays; estimated physical units are disclosed; no ruler restores off-screen | 2-3 days |
| 5. Product finish | Settings, shortcuts, context menus, persistence, icon, manual, accessibility labels | All core operations work without privacy prompts; keyboard-only workflow is complete | 2-3 days |
| 6. Verification | Unit/UI tests, multi-monitor manual matrix, release notes, version bump and local install | Tests pass; no regressions to AI History or RSync; release build is signed and installed | 1-2 days |

Expected total for a polished Free Ruler-class first release: **10-16 engineering
days**. A rough prototype could appear in 3-5 days, but shipping it at PowerToys'
existing quality level requires the multi-display, Retina, restoration, and input
work above.

### Measurement semantics that must be explicit

- **Point:** one AppKit layout unit. This is what window frames and SwiftUI layout
  use.
- **Backing pixel:** a pixel in the window's backing store. Use AppKit backing
  coordinate conversion rather than multiplying blindly by a scale factor.
- **Physical unit:** calculated from display pixel geometry and
  `CGDisplayScreenSize`. Apple may estimate the physical size when EDID is missing,
  so a calibrated value is more trustworthy than an unlabeled default.
- **Global coordinates:** AppKit's multi-display coordinate space can include
  negative origins. Convert through the ruler window and owning screen instead of
  assuming the main display begins at `(0, 0)`.

Relevant Apple APIs are [`NSScreen.backingScaleFactor`](https://developer.apple.com/documentation/appkit/nsscreen/backingscalefactor),
the screen/view backing conversion methods, and
[`CGDisplayScreenSize`](https://developer.apple.com/documentation/coregraphics/cgdisplayscreensize(_:)).

### Test matrix

- 1x external display, 2x built-in display, and mixed 1x/2x arrangement.
- External display placed left, right, above, and below the primary display.
- Rotated display and display disconnect while rulers are visible.
- Four zero corners, both orientations, grouped and independent rulers.
- Minimum/maximum resizing and rulers partially outside a visible screen.
- Points versus backing pixels at every available display scale.
- Missing/estimated physical display size and manual calibration.
- Light/dark appearance, all supported ruler colors, reduced transparency, and
  increased contrast.
- Relaunch restoration with the original display missing.

### Post-version-1 developer features

Add these only after the manual ruler is stable:

1. Screen-wide crosshair and draggable guide lines, still without screen capture.
2. Click-drag rectangle measurement with copied `width x height`, origin, and
   center coordinates.
3. Copy formats for CSS, SwiftUI, CGRect, JSON, and plain text.
4. Aspect-ratio lock and common presets such as 16:9, 4:3, and 1:1.
5. Measurement pins/history that remain until dismissed.
6. Accessibility-assisted snapping to another app's exposed UI element frames.
   This is optional and requires Accessibility permission.
7. PowerToys-style color-edge spacing detection using ScreenCaptureKit. This is a
   separate mode that requires Screen Recording permission and should explain why
   before prompting.
8. Pixel loupe and color sampling, preferably through `NSColorSampler` where that
   avoids broad capture consent.

Do not put OCR, screenshot annotation, window management, or a general design
inspector into the first release. Those turn a low-risk ruler into several larger
permission-heavy products at once.

## Primary source index

- [Microsoft PowerToys utility index and source links](https://learn.microsoft.com/en-us/windows/powertoys/)
- [Microsoft PowerToys source repository](https://github.com/microsoft/PowerToys)
- [Apple ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit)
- [Apple Vision text recognition](https://developer.apple.com/documentation/vision/recognizetextrequest)
- [Apple Quick Look](https://developer.apple.com/documentation/quicklook)
- [Apple Quick Look Thumbnailing](https://developer.apple.com/documentation/quicklookthumbnailing)
- [Apple Finder Sync](https://developer.apple.com/documentation/findersync)
- [Apple Accessibility AXUIElement](https://developer.apple.com/documentation/applicationservices/axuielement_h)
- [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Free Ruler official repository](https://github.com/pascalpp/FreeRuler)
- [Rectangle official site](https://rectangleapp.com/)
- [Karabiner-Elements official site and documentation](https://karabiner-elements.pqrs.org/)
- [MonitorControl official repository](https://github.com/MonitorControl/MonitorControl)
