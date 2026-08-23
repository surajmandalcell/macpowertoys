# Product

<!-- impeccable:product-schema 1 -->

## Platform

macOS

## Users

Mac power users who want focused system utilities in one native application.
They value fast shortcuts, reliable multi-monitor windows, low background cost,
and clear control over system changes.

## Product Purpose

MacPowerToys provides on-demand tools for screen text extraction, input-device
control, system cleanup, storage inspection, system monitoring, file work, and
developer workflows. Success means each tool works without setup fuss and does
not tax the Mac when its window is closed.

## Positioning

MacPowerToys combines focused native utilities in one coherent host while each
tool keeps its own window, workflow, state, and resource lifetime.

## Operating Context

- People use more than one display, including layouts with negative or large
  window coordinates.
- Text Extractor starts from its existing global shortcut or its window.
- Input Devices controls external mice and built-in or external trackpads as
  distinct hardware classes.
- Mole supports quick cleanup, guided cleanup, and analysis-only use. Settings
  choose the default, while the other modes remain one or two actions away.
- Power Stats shows detailed monitoring only while its window is open. Its
  optional menu-bar summary uses a lightweight configurable interval.

## Capabilities and Constraints

- Keep the current Text Extractor shortcut while matching useful reference
  behavior, recognition options, history, feedback, and settings.
- Restore every window's display and position before display. Restore the last
  user-selected size for resizable windows and the defined size for fixed tools.
- Input Devices includes independent mouse and trackpad controls for scrolling
  direction, horizontal scrolling, and smooth scrolling where public macOS APIs
  permit reliable behavior.
- Mole uses a large MacPowerToys workspace with storage drill-down visuals and
  explicit safety before destructive work.
- Power Stats may place individual metrics or one grouped summary in the menu
  bar. Detailed sampling stops when its window closes.
- Use public APIs, request only required permissions, and keep CPU, memory,
  timers, event monitors, and retained data bounded.
- Research must confirm Mole distribution, licensing, permissions, and supported
  macOS integration before packaging or installation.

## Brand Commitments

- Product name: MacPowerToys.
- Tool names: Text Extractor, Ruler, Input Devices, Mole, and Power Stats.
- Follow `DESIGN.md` and the current native SwiftUI and AppKit surfaces.
- Use `/Users/surajmandal/dev/_clone/vorssaint-utils` as a read-only code and
  documentation reference.

## Evidence on Hand

- `DESIGN.md` and `docs/screenshots/` define the current visual system.
- Existing Text Extractor, Ruler, window-state, menu-bar, and workspace code
  provide implementation seams.
- `vorssaint-utils/README.md` and its source provide reference features and
  documentation structure.
- No performance claims, cleanup benchmarks, or third-party endorsements are
  approved. Future work must measure or label illustrative values.

## Product Principles

1. Make the main action immediate and make failure visible.
2. Remember the user's window placement across displays.
3. Run heavy work only while the related tool is in use.
4. Show impact and recovery before destructive cleanup.
5. Reuse proven reference behavior, then fit MacPowerToys architecture and UX.

## Accessibility & Inclusion

Support keyboard access, clear focus, VoiceOver labels, reduced motion, reduced
transparency, increased contrast, scalable text, and status cues beyond color.
